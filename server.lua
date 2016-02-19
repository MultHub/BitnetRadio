local updateURL = "https://raw.github.com/MultHub/BitnetRadio/master/server.lua"

local bitnet = peripheral.find("bitnet_tower")

local conf = {
  name = "UNNAMEDRADIO",
  sendDelay = 5,
}
local f = fs.open("radio.conf", "r")

if not f then
  if not fs.exists("radio.conf") then
    printError("No config file, creating one")
    print("Change the default settings in radio.conf")
    local f = fs.open("radio.conf", "w")
    f.write(textutils.serialize(conf))
    f.close()
  else
    print("Invalid config")
  end
  return false
end
conf = textutils.unserialize(f.readAll())
f.close()

local function saveConfig()
  local f = fs.open("radio.conf", "w")
  f.write(textutils.serialize(conf))
  f.close()
end

local buffer = {}
local bufferpos = 1

local running = true
local broadcasting = false

local cmds = {
  help = {"[command/page]", "Command help",
  "Display list of commands and command help"},
  broadcast = {"[true/false]", "Broadcast status",
  "Get or set broadcast status",fn=function(value)
    if value == "true" then
      broadcasting = true
    elseif value == "false" then
      broadcasting = false
    end
    if broadcasting then
      print("Broadcasting")
    else
      print("Not broadcasting")
    end
  end},
  stop = {"", "Stop radio server",
  "Stop the radio server and return to shell",fn=function()
    running = false
  end},
  config = {"[see full description]", "Edit config",
  "Get and set config values\n" ..
  "/config <name> <value>: set\n" ..
  "/config <name>: get",fn=function(name, value)
    if not name then
      for k, v in pairs(conf) do
        print(k.." = "..tostring(v))
      end
      return
    end
    if value then
      conf[name] = tonumber(value) or value
      saveConfig()
    end
    print(name.." = "..tostring(conf[name]))
  end},
  clear = {"", "Clear the console", fn=function()
    term.clear()
    term.setCursorPos(1, 1)
  end},
  clearbuffer = {"", "Clear text buffer", fn=function()
    buffer = {}
    bufferpos = 1
  end},
  printbuffer = {"", "Print text buffer", fn=function()
    for i, v in ipairs(buffer) do
      print(i..":"..v)
    end
  end},
  update = {"", "Update the server", "Pull latest version from GitHub", fn=function()
    local r = http.get(updateURL)
    if not r then
      printError("Error downloading update")
      return
    end
    local f = fs.open(shell.getRunningProgram(), "w")
    f.write(r.readAll())
    f.close()
    r.close()
    running = false
    print("Restart to use new version")
  end},
}

function cmds.help.fn(command)
  if command and not tonumber(command) then
    if not cmds[command] then
      printError("No help available")
    else
      printError("/"..command.." "..cmds[command][1])
      print(cmds[command][3] or cmds[command][2] or "No help available")
    end
  else
    local page = tonumber(command) or 1
    local w, h = term.getSize()
    local cmdHelp = {}
    for i, v in pairs(cmds) do
      local cmd = "/" .. i
      if v[1] ~= "" then
        cmd = cmd .. " " .. v[1]
      end
      if v[2] then
        cmd = cmd .. ": " .. v[2]
      elseif v[3] then
        cmd = cmd .. ": " .. v[3]
      end
      if #cmd > w then
        cmd = cmd:sub(1, w - 4) .. " ..."
      end
      table.insert(cmdHelp, cmd)
    end
    table.sort(cmdHelp)
    print("--- Help: Page "..page.." ---")
    for i = 1 + (page - 1) * (h - 2), page * (h - 2) do
      if cmdHelp[i] then
        print(cmdHelp[i])
      end
    end
  end
end

function parseCommand(str)
  local parts = {}
  local tmp = ""
  local escaping = false
  for i = 1, #str do
    if escaping then
      escaping = false
      tmp = tmp .. str:sub(i, i)
    else
      if str:sub(i, i) == " " then
        table.insert(parts, tmp)
        tmp = ""
      elseif str:sub(i, i) == "\\" then
        escaping = true
      else
        tmp = tmp .. str:sub(i, i)
      end
    end
  end
  table.insert(parts, tmp)
  local cname = table.remove(parts, 1)
  if cmds[cname] then
    cmds[cname].fn(unpack(parts))
  else
    printError("Unknown command.")
  end
end

local history = {}

term.clear()
term.setCursorPos(1, 1)
if term.isColor() then
  term.setTextColor(colors.yellow)
end
print("BitnetRadio server - "..conf.name)

parallel.waitForAny(function()
  while running do
    if broadcasting then
      bufferpos = ((bufferpos - 1) % #buffer) + 1
      bitnet.transmit({"radio",conf.name,buffer[bufferpos]})
      bufferpos = (bufferpos % #buffer) + 1
      sleep(conf.sendDelay)
    else
      sleep(0)
    end
  end
end, function()
  while running do
    if term.isColor() then
      term.setTextColor(colors.yellow)
    end
    write("radio> ")
    term.setTextColor(colors.white)
    local str = read(nil, history)
    if str:gsub(" ", "") ~= "" then
      table.insert(history, str)
      if str:sub(1, 1) == "/" then
        parseCommand(str:sub(2))
      else
        table.insert(buffer, str)
      end
    end
  end
end)
