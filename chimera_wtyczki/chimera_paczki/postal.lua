-- Shared registry of the exact office rooms verified in beta.13 data/world.
-- Aliases identify only these offices; they never create a route or imply
-- that the current profile has a safe path to the destination.
local OFFICES = {
    { id="6f2c03461c2f1438", name="Poczta", city="Nuln", staticNuln=true,
        aliases={"Poczta wolnego miasta Nuln"} },
    { id="907327356ecc2f87", name="Glowna sala poczty w Krainie Zgromadzenia", city="Kraina Zgromadzenia",
        forms={"Kraina Zgromadzenia","Krainie Zgromadzenia"} },
    { id="200aff4d957642cd", name="Poczta", city="Bissingen" },
    { id="54fa7e4634a30c23", name="Poczta Ubersreik", city="Ubersreik" },
    { id="315106e45b840273", name="Poczta miasta Kreutzhofen", city="Kreutzhofen",
        forms={"Kreutzhofen","Kreutzhoffen"} },
    { id="e202c7893bf8fb55", name="Poczta w Quenelles", city="Quenelles" },
    { id="78c41b4fab38b2b5", name="Urzad pocztowy Varieno", city="Varieno" },
    { id="e8337482d2ae8342", name="Poczta w Jouinard", city="Jouinard" },
    { id="269ff0c7899bbd55", name="Poczta w Campogrotta", city="Campogrotta" },
    { id="0a647e20ca6f97f7", name="Urzad pocztowy Urbimo", city="Urbimo" },
    { id="a99c7f47e46ffcc8", name="Glowny urzad pocztowy Athkatli", city="Athkatla",
        forms={"Athkatla","Athkatli"} },
    { id="80f9aa1ca9d14ae6", name="Poczta", city="Wrota Baldura",
        forms={"Wrota Baldura","Wrotach Baldura"}, aliases={"Poczta we Wrotach Baldura","Urzad pocztowy we Wrotach Baldura"} },
    { id="bbfb868db7d0899d", name="Poczta w Beregoscie", city="Beregost", forms={"Beregost","Beregoscie"} },
    { id="507ac12170e468aa", name="Filia Imperialnej Poczty", city="Bogenhafen",
        aliases={"Filia Imperialnej Poczty w Bogenhafen"} },
    { id="381bc4bb1fc81f0a", name="Urzad pocztowy", city="Crimmor" },
    { id="842de8139814c827", name="Urzad pocztowy", city="Toscania", forms={"Toscania","Toscanii"} },
    { id="cce045477b087e33", name="Urzad pocztowy", city="Nashkel" },
    { id="4101e9db0e55ab41", name="Urzad pocztowy", city="Pod Pomocna Dlonia" },
    { id="2af1b52e73cf5416", name="Poczta w Jaskare", city="Jaskare" },
    -- The old named room does not process courier parcels. The nearby
    -- Poczta is the counter confirmed by both handover and parcel-board ACKs.
    { id="c55c2924e506dd7f", name="Poczta", city="Karak Varn",
        forms={"Karak Varn","Karak-Varn","Krolestwa Krasnoludow","Krolestwach Krasnoludow"} },
    { id="b172d89a6a1e8023", name="Poczta", city="Candlekeep" },
    { id="35da6d2dd7e84f19", name="Poczta", city="Athel Loren" },
    -- These registry labels denote a domain/faction, not an unambiguous city.
    -- Keep their specific office labels instead of generating regional aliases.
    { id="28b482449fad7190", name="Poczta w Krawej Fortecy Gruumsha", city="Faerun", forms=false },
    { id="2f613cc0de125521", name="Filia Poczty Imperialnej", city="Najemnicy", forms=false,
        aliases={"Filia Poczty Imperialnej Najemnicy"} },
}
local ACCENTS={
    ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z",
}
local function norm(value)
    if type(value)~="string" then return "" end
    value=value:gsub("\27%[[%d;]*[mK]",""):gsub(" "," ")
    for accent,ascii in pairs(ACCENTS) do value=value:gsub(accent,ascii) end
    return (value:lower():gsub("%s+"," "):gsub("^%s+",""):gsub("[%s%.]+$",""))
end
local function copy(record)
    return {id=record.id,name=record.name,city=record.city,staticNuln=record.staticNuln}
end
local GENERIC={ ["poczta"]=true,["urzad pocztowy"]=true,
    ["filia imperialnej poczty"]=true,["filia poczty imperialnej"]=true }
local TEMPLATES={"Poczta %s","Poczta w %s","Poczta miasta %s","Poczta miasteczka %s",
    "Urzad pocztowy %s","Urzad pocztowy w %s","Urzad pocztowy miasta %s"}
local labels={}
local function add(label,office)
    local key=norm(label)
    if key=="" or GENERIC[key] then return end
    local previous=labels[key]
    if previous==nil then labels[key]=office
    elseif previous and previous.id~=office.id then labels[key]=false end
end
for _,office in ipairs(OFFICES) do
    add(office.name,office)
    for _,label in ipairs(office.aliases or {}) do add(label,office) end
    if office.forms~=false then
        for _,form in ipairs(office.forms or {office.city}) do
            for _,template in ipairs(TEMPLATES) do add(string.format(template,form),office) end
        end
    end
end
local api={version="1.5.7"}
function api.disabled(id)
    if id=="3de8d58adb6dbe9b" then return "stara poczta Karak Varn nie obsluguje paczek kurierskich" end
end
function api.catalogue()
    local out={}
    for _,office in ipairs(OFFICES) do out[#out+1]=copy(office) end
    return out
end
api.catalog=api.catalogue
function api.resolve(label)
    local office=labels[norm(label)]
    return office and copy(office) or nil
end
return api
