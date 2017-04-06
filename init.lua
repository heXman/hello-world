-- General parameters of the peripherals
LM75_addr = 0x4F
sda=3
scl=2
led1 = 1
gpio.mode(led1, gpio.OUTPUT)
--configuring internal ADC
if adc.force_init_mode(adc.INIT_ADC)
then
  node.restart()
  return -- don't bother continuing, the restart is scheduled
end

print("Starting voltage (mV):", adc.read(0))

-- wifi config
cfg={}
cfg.ssid="xontrol"
cfg.pwd="12345678"
wifi.ap.config(cfg)
wifi.setmode(wifi.SOFTAP)
print ("ESP mode "..wifi.getmode())
-- dhcp config
dhcp_config ={}
dhcp_config.start = "192.168.1.100"
wifi.ap.dhcp.config(dhcp_config)
wifi.ap.dhcp.start()
tmr.delay(1000);
ip = wifi.ap.getip()
print(ip)
-- Here the wifi is set up and running

-- I2C functions
i2c.setup(0, sda, scl, i2c.SLOW)

function read_reg(dev_addr,bytes)
    i2c.start(0)
    i2c.start(0)
    i2c.address(0, dev_addr, i2c.RECEIVER)
    c = i2c.read(0, bytes) -- bytes read and returned
    i2c.stop(0)
    return c
end
function write_reg(dev_addr, reg_addr, val)
    i2c.start(0)
    i2c.address(0, dev_addr, i2c.TRANSMITTER)
    i2c.write(0, val)
    i2c.stop(0)
    return c
end
function measureTemp()
    reg = read_reg(LM75_addr,2) --for brd#3
    temp=10*tonumber(string.byte(reg,1))+(tonumber(string.byte(reg,2))/32)
    print(string.format("Temperature= %d.%d \r\n",temp/10,temp-(temp/10)*10)) 
    return temp/10
end
---------------- End of I2C functions
-- first dummy measurement
 temp=measureTemp()

--- Here go global variables 
 OutputStatus=0
 currThr=0 -- current Threshold level
 ThrFlag=0 -- do we use threshold limiting or no
 ThrType='TH' -- current threshold type
-- Simple web server to set up threshold and direct control
srv=net.createServer(net.TCP) srv:listen(80,function(conn)
    conn:on("receive",function(conn,payload)
    --next row is for debugging output only
    print(payload)
    function ctrlpower()
        override=string.sub(payload,command[2]+1,command[2]+2) --chop 2 symbols
        if override=="ON"  then ThrFlag=0 gpio.write(led1,gpio.HIGH) OutputStatus=1 return end
        if override=="OF" then ThrFlag=0 gpio.write(led1,gpio.LOW) OutputStatus=0 return end
        if override=="LI" then 
             command={string.find(payload,"thr=")}
            thr=string.sub(payload,command[2]+1,#payload)
            thr=string.match(thr,"%d+");
            if thr then
                print('threshold '..thr..'\r\n')
                currThr=thr
                  command={string.find(payload,"type=")}
                  type=string.sub(payload,command[2]+1,command[2]+2) --chop 2 symbols
                  ThrType=type
                  ThrFlag=1
            end
        return end
       
    end
    --parse position POST value from header
    command={string.find(payload,"ovr=")}
    --If POST value exist, set LED power
    if command[2]~=nil then ctrlpower()end
     temp=measureTemp()
     lumi=adc.read(0)
     buf = "<h3> Current temperature:"..temp.." °C</h3>";
     buf = buf.."<h3> Current luminocity:"..lumi.." units</h3>";
     buf = buf.."<h3> Current output status:"..OutputStatus.."</h3>";
      buf = buf.."<h3> Current output status:"..OutputStatus.."</h3>";
     
    conn:send('HTTP/1.1 200 OK\n\n')
    conn:send('<!DOCTYPE HTML>\n')
    conn:send('<html>\n')
    conn:send('<head><meta  content="text/html; charset=utf-8">\n')
    conn:send('<title>ESP8266</title></head>\n')
    conn:send('<body><h1>Simple automatic control</h1>\n')
    conn:send(buf)
    conn:send('<form action="" method="POST">\n')
    conn:send('<button type="submit" name="ovr" value="OF">OFF</button>\n')
    conn:send('<button type="submit" name="ovr" value="ON">ON</button><br>\n')
    conn:send('Threshold  value:<input type="number" name="thr"><br>\n')
     conn:send('<h3>Threshold type:</h3>\n')
    conn:send('<input type="radio" name="type" value="TH" checked> Temperature high<br>')
    conn:send('<input type="radio" name="type" value="TL"> Temperature low<br>')
    conn:send('<input type="radio" name="type" value="LH"> Luminocity high<br>')
    conn:send('<input type="radio" name="type" value="LL"> Luminocity low<br>')
    conn:send('<button type="submit" name="ovr" value="LI">Threshold</button></form>\n')
    conn:send('</body></html>\n')
    conn:on("sent",function(conn) conn:close() end)
    end)
end)
b=adc.read(0);
print(b)
function thresholdEvaluate()
    if ThrFlag==1 then 
        temp=measureTemp()
        lumi=adc.read(0)
        currThr=tonumber(currThr)
        print('l='..lumi..' t='..temp..' '..ThrType..'='..currThr..'\r\n')
        if ThrType=='TH' then  
            if temp>currThr then  gpio.write(led1,gpio.HIGH) OutputStatus=1
            else gpio.write(led1,gpio.LOW) OutputStatus=0 end
        end
        if ThrType=='TL' then 
            if temp<currThr then  gpio.write(led1,gpio.HIGH) OutputStatus=1
            else gpio.write(led1,gpio.LOW) OutputStatus=0 end
        end
        if ThrType=='LH' then 
            if lumi>currThr then  gpio.write(led1,gpio.HIGH) OutputStatus=1
            else gpio.write(led1,gpio.LOW) OutputStatus=0 end
        end
        if ThrType=='LL' then 
            if lumi<currThr then  gpio.write(led1,gpio.HIGH) OutputStatus=1
            else gpio.write(led1,gpio.LOW) OutputStatus=0 end
        end
    end
end
tmr.register(0, 2000, tmr.ALARM_AUTO, thresholdEvaluate)
tmr.start(0);
