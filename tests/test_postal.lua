-- Pure postal-label tests; run from any directory with texlua <path>/test_postal.lua.
local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tests/test_postal%.lua$") or (script == "test_postal.lua" and ".." or ".")
package.path = root .. "/chimera_wtyczki/?.lua;" .. root .. "/chimera_wtyczki/?/init.lua;" .. package.path
local postal = require("chimera_paczki.postal")
local passed = 0
local function eq(expected, actual, why)
    assert(expected == actual, (why or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, body)
    local ok, problem = pcall(body)
    if not ok then error(name .. ": " .. tostring(problem), 0) end
    passed = passed + 1
    print("OK " .. name)
end

local expected = {
    { id="6f2c03461c2f1438", name="Poczta", city="Nuln", staticNuln=true },
    { id="907327356ecc2f87", name="Glowna sala poczty w Krainie Zgromadzenia", city="Kraina Zgromadzenia" },
    { id="200aff4d957642cd", name="Poczta", city="Bissingen" },
    { id="54fa7e4634a30c23", name="Poczta Ubersreik", city="Ubersreik" },
    { id="315106e45b840273", name="Poczta miasta Kreutzhofen", city="Kreutzhofen" },
    { id="e202c7893bf8fb55", name="Poczta w Quenelles", city="Quenelles" },
    { id="78c41b4fab38b2b5", name="Urzad pocztowy Varieno", city="Varieno" },
    { id="e8337482d2ae8342", name="Poczta w Jouinard", city="Jouinard" },
    { id="269ff0c7899bbd55", name="Poczta w Campogrotta", city="Campogrotta" },
    { id="0a647e20ca6f97f7", name="Urzad pocztowy Urbimo", city="Urbimo" },
    { id="a99c7f47e46ffcc8", name="Glowny urzad pocztowy Athkatli", city="Athkatla" },
    { id="80f9aa1ca9d14ae6", name="Poczta", city="Wrota Baldura" },
    { id="bbfb868db7d0899d", name="Poczta w Beregoscie", city="Beregost" },
    { id="507ac12170e468aa", name="Filia Imperialnej Poczty", city="Bogenhafen" },
    { id="381bc4bb1fc81f0a", name="Urzad pocztowy", city="Crimmor" },
    { id="842de8139814c827", name="Urzad pocztowy", city="Toscania" },
    { id="cce045477b087e33", name="Urzad pocztowy", city="Nashkel" },
    { id="4101e9db0e55ab41", name="Urzad pocztowy", city="Pod Pomocna Dlonia" },
    { id="2af1b52e73cf5416", name="Poczta w Jaskare", city="Jaskare" },
    { id="c55c2924e506dd7f", name="Poczta", city="Karak Varn" },
    { id="b172d89a6a1e8023", name="Poczta", city="Candlekeep" },
    { id="35da6d2dd7e84f19", name="Poczta", city="Athel Loren" },
    { id="28b482449fad7190", name="Poczta w Krawej Fortecy Gruumsha", city="Faerun" },
    { id="2f613cc0de125521", name="Filia Poczty Imperialnej", city="Najemnicy" },
}

test("catalogue has the exact twenty-four working courier offices", function()
    eq("1.5.7", postal.version)
    local rows = postal.catalogue()
    eq(24, #rows)
    local by_id = {}
    for _, row in ipairs(rows) do
        assert(type(row.id) == "string" and not by_id[row.id], "missing or duplicate office hash")
        by_id[row.id] = row
    end
    for _, want in ipairs(expected) do
        local row = assert(by_id[want.id], "missing " .. want.city)
        eq(want.name, row.name, want.city .. " title")
        eq(want.city, row.city, want.city .. " city")
        eq(want.staticNuln == true, row.staticNuln == true, want.city .. " static marker")
    end
    eq(24, #postal.catalog())
end)

for _, want in ipairs(expected) do
    local label
    if want.city == "Faerun" then label = "Poczta w Krawej Fortecy Gruumsha"
    elseif want.city == "Najemnicy" then label = "Filia Poczty Imperialnej Najemnicy"
    else label = "Urzad pocztowy w " .. want.city end
    test("qualified known-office label: " .. label, function()
        local row = assert(postal.resolve(label), "qualified label was not resolved")
        eq(want.id, row.id)
        eq(want.name, row.name)
        eq(want.city, row.city)
    end)
end

local observed = {
    { "Urzad pocztowy w Nuln", "6f2c03461c2f1438" },
    { "Poczta wolnego miasta Nuln", "6f2c03461c2f1438" },
    { "Poczta w Urbimo", "0a647e20ca6f97f7" },
    { "Urzad pocztowy w Urbimo", "0a647e20ca6f97f7" },
    { "Urzad pocztowy w Varieno", "78c41b4fab38b2b5" },
    { "Poczta miasteczka Varieno", "78c41b4fab38b2b5" },
    { "Poczta w Karak Varn", "c55c2924e506dd7f" },
    { "Urzad pocztowy Karak-Varn", "c55c2924e506dd7f" },
    { "Poczta w Kreutzhoffen", "315106e45b840273" },
    { "Urzad pocztowy w Crimmor", "381bc4bb1fc81f0a" },
}
test("all ten formerly missing board aliases resolve to their known-city hashes", function()
    for _, item in ipairs(observed) do eq(item[2], assert(postal.resolve(item[1]), item[1]).id, item[1]) end
end)

test("normalization folds Polish characters spacing case and final periods", function()
    eq("6f2c03461c2f1438", assert(postal.resolve("  URZĄD   POCZTOWY  W  NULN.  ")).id)
    eq("907327356ecc2f87", assert(postal.resolve(" Poczta  w  Krainie   Zgromadzenia. ")).id)
    eq("80f9aa1ca9d14ae6", assert(postal.resolve("Urząd pocztowy w Wrota Bałdura")).id)
    eq("6f2c03461c2f1438", assert(postal.resolve("Poczta wolnego miasta Nuln.")).id)
end)

test("unqualified generic titles remain ambiguous", function()
    for _, label in ipairs({ "Poczta", "Urzad pocztowy", "Urząd pocztowy.",
        "Filia Imperialnej Poczty", "Filia Poczty Imperialnej", "Glowny urzad pocztowy" }) do
        eq(nil, postal.resolve(label), label)
    end
end)

test("special region records require their actual named office labels", function()
    for _, label in ipairs({ "Poczta w Faerun", "Urzad pocztowy w Faerun", "Poczta Faerun",
        "Poczta w Najemnicy", "Urzad pocztowy w Najemnicy", "Poczta Najemnicy" }) do
        eq(nil, postal.resolve(label), label)
    end
end)

test("unknown cities typos and substring prefix suffix guesses are rejected", function()
    for _, label in ipairs({ "Poczta w Nieznanym Miescie", "Urzad pocztowy w Altdorf", "Poczta w Nulnn",
        "Poczta w Urbim", "Poczta wolnego miasta Nulnn", "Nuln poczta jakas", "Przed poczta w Nuln",
        "X Poczta w Nuln", "Poczta w Nuln dodatkowa", "Urzad pocztowy w Nuln obok rynku",
        "Glowny urzad pocztowy Athkatli i Nuln", "Poczta w Quenelles poludniowa",
        "Filia Poczty Imperialnej Najemnicy obok", "Poczta w Krawej Fortecy Gruumsha extra", "" }) do
        eq(nil, postal.resolve(label), label)
    end
end)

test("target labels do not accept a bare city name or room hash", function()
    for _, row in ipairs(expected) do
        eq(nil, postal.resolve(row.city), row.city)
        eq(nil, postal.resolve(row.id), row.id)
    end
    eq(nil, postal.resolve(nil))
    eq(nil, postal.resolve(123))
    eq(nil, postal.resolve({ city="Nuln" }))
end)

test("every resolve and catalogue result is an isolated copy", function()
    local first = assert(postal.resolve("Poczta w Nuln"))
    local second = assert(postal.resolve("Urzad pocztowy w Nuln"))
    assert(first ~= second)
    first.id, first.name, first.city, first.staticNuln = "changed", "Changed", "Changed", false
    eq("6f2c03461c2f1438", second.id)
    eq("Nuln", second.city)
    eq(true, second.staticNuln)
    local rows = postal.catalogue()
    local alias = postal.catalog()
    assert(rows ~= alias and rows[1] ~= alias[1])
    rows[1].id, rows[1].city = "mutated", "mutated"
    table.remove(rows)
    eq(24, #postal.catalogue())
    local again = assert(postal.resolve("Poczta w Nuln"))
    eq("6f2c03461c2f1438", again.id)
    eq("Nuln", again.city)
    eq(true, again.staticNuln)
end)

test("Karak Varn and legacy dwarf-region labels point to the working courier counter only",function()
    for _,label in ipairs({"Poczta w Karak Varn","Urzad pocztowy Karak-Varn","Urzad pocztowy w Karak Varn",
        "Poczta w Krolestwa Krasnoludow","Urzad pocztowy w Krolestwach Krasnoludow"}) do
        local office=assert(postal.resolve(label),label)
        eq("c55c2924e506dd7f",office.id,label);eq("Karak Varn",office.city);eq("Poczta",office.name)
    end
    local count=0
    for _,office in ipairs(postal.catalogue()) do
        assert(office.id~="3de8d58adb6dbe9b","broken office cannot be selected automatically")
        if office.id=="c55c2924e506dd7f" then count=count+1 end
    end
    eq(1,count,"one city must have one working parcel counter")
end)
test("disabled courier rooms are identified only by their exact known hash",function()
    assert(type(postal.disabled("3de8d58adb6dbe9b"))=="string")
    for _,value in ipairs({"c55c2924e506dd7f","6f2c03461c2f1438","Urzad pocztowy w Karak Varn","unknown",123,{}}) do
        eq(nil,postal.disabled(value))
    end
    eq(nil,postal.disabled(nil));eq(nil,postal.resolve("3de8d58adb6dbe9b"))
end)

print("PASS " .. passed .. " postal catalogue and exact-label tests")
