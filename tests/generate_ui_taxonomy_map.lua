-- Generates or validates the reviewable SiK UI taxonomy map from the runtime registry.
-- Run with --write only when intentionally updating the approved HTML master.

local probe = io.open("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeProduct.lua", "rb")
local fromRepo = probe ~= nil
if probe then probe:close() end
local ROOT = fromRepo and "" or "GlobalStorageSiK-Repo/"
local DOC_ROOT = fromRepo and "../" or ""
local SHARED = ROOT .. "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
local TRANSLATIONS = SHARED .. "Translate/ES/IG_UI.json"
local PRODUCT = SHARED .. "GS_NativeProduct.lua"
local OUTPUT = DOC_ROOT .. "Documentacion/UI/taxonomia-categorias.html"

GlobalStorageSiK = {}
dofile(SHARED .. "GS_NativeTaxonomyRegistry.lua")
dofile(SHARED .. "GS_NativeTaxonomy_GroundTruth.lua")

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local value = handle:read("*a")
	handle:close()
	return value
end

local function escapeHtml(value)
	return tostring(value or "")
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
end

local labels = {}
for key, value in readFile(TRANSLATIONS):gmatch('"IGUI_GS_NativeTax_([%w_]+)"%s*:%s*"([^"]*)"') do
	labels[key] = value
end

local colors = {}
local productSource = readFile(PRODUCT)
local colorBlock = assert(productSource:match("local L1_COLORS%s*=%s*{(.-)\n}"),
	"GS_NativeProduct.lua does not expose the expected L1_COLORS block")
for key, r, g, b in colorBlock:gmatch("([%w_]+)%s*=%s*{%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*}") do
	colors[key] = { tonumber(r), tonumber(g), tonumber(b) }
end

local function pathKey(l1, l2, l3)
	local value = l1
	if l2 then value = value .. "/" .. l2 end
	if l3 then value = value .. "/" .. l3 end
	return value
end

local examples = {}
for _, case in ipairs(GlobalStorageSiK.NativeTaxonomyGroundTruth.cases or {}) do
	if case.fullType and case.expectedL1 and case.expectedL2 then
		local l3 = type(case.expectedL3) == "string" and case.expectedL3 or nil
		local key = pathKey(case.expectedL1, case.expectedL2, l3)
		if not examples[key] then examples[key] = case.fullType end
	end
end

local l1Order = {
	"combat", "food_drink", "tools", "materials", "medicine",
	"clothing_protection", "containers", "knowledge_media", "electronics_power",
	"vehicles", "survival_outdoors", "home_leisure_collection", "other",
	"globalstoragesik",
}

local function translated(key)
	return labels[key] or key:gsub("_", " ")
end

local function sortedKeys(values)
	local keys = {}
	for key in pairs(values or {}) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		local al, bl = translated(a), translated(b)
		if al == bl then return a < b end
		return al < bl
	end)
	return keys
end

local lines = {}
local function emit(value) lines[#lines + 1] = value end
local tree = GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
local terminalCount, coveredCount, l2Count = 0, 0, 0

emit("<!doctype html>")
emit('<html lang="es" data-palette="graphite">')
emit("<head>")
emit('  <meta charset="utf-8">')
emit('  <meta name="viewport" content="width=device-width,initial-scale=1">')
emit("  <title>Global Storage SiK · Mapa de categorías</title>")
emit('  <link rel="stylesheet" href="assets/sik-ui.css">')
emit("</head>")
emit("<body>")
emit('  <main class="sik-stage sik-taxonomy-stage">')
emit('    <section class="sik-window sik-taxonomy-window" data-surface-id="taxonomy-map" aria-label="Mapa de categorías de Global Storage SiK">')
emit('      <header class="sik-window-header">')
emit('        <strong>Global Storage SiK</strong><span class="sik-window-context">Mapa de categorías</span>')
emit('        <button class="sik-window-close" type="button" aria-label="Cerrar"></button>')
emit("      </header>")
emit('      <section class="sik-taxonomy-content">')
emit('        <div class="sik-block-header" data-help="Cada familia usa el mismo color que el inventario de red. Las rutas y ejemplos proceden del registro y GroundTruth.">Taxonomía completa <span class="sik-taxonomy-count">L1 → L2 → L3</span></div>')
emit('        <div class="sik-taxonomy-legend" aria-label="Leyenda">')
emit('          <span><i class="sik-taxonomy-dot is-covered"></i>Ejemplo verificado</span>')
emit('          <span><i class="sik-taxonomy-dot is-uncovered"></i>Sin ejemplo curado</span>')
emit('          <span>El color se hereda de la familia L1</span>')
emit("        </div>")
emit('        <div class="sik-taxonomy-grid">')

for _, l1 in ipairs(l1Order) do
	local l2s = assert(tree[l1], "missing expected L1 " .. l1)
	local color = assert(colors[l1], "missing L1 color " .. l1)
	local r = math.floor(color[1] * 255 + 0.5)
	local g = math.floor(color[2] * 255 + 0.5)
	local b = math.floor(color[3] * 255 + 0.5)
	emit(string.format('          <details class="sik-taxonomy-family" open data-l1="%s" data-color-rgb="%.2f,%.2f,%.2f" style="--sik-taxonomy-color:rgb(%d,%d,%d)">',
		escapeHtml(l1), color[1], color[2], color[3], r, g, b))
	emit('            <summary class="sik-taxonomy-family-header"><span class="sik-taxonomy-swatch"></span><strong>'
		.. escapeHtml(translated(l1)) .. '</strong><code>' .. escapeHtml(l1) .. '</code></summary>')
	emit('            <div class="sik-taxonomy-groups">')
	for _, l2 in ipairs(sortedKeys(l2s)) do
		l2Count = l2Count + 1
		local l3s = l2s[l2]
		emit(string.format('              <section class="sik-taxonomy-group" data-l1="%s" data-l2="%s">', escapeHtml(l1), escapeHtml(l2)))
		emit('                <div class="sik-taxonomy-group-header"><strong>' .. escapeHtml(translated(l2))
			.. '</strong><code>' .. escapeHtml(l2) .. '</code></div>')
		emit('                <div class="sik-taxonomy-leaves">')
		if #l3s == 0 then
			terminalCount = terminalCount + 1
			local example = examples[pathKey(l1, l2)]
			if example then coveredCount = coveredCount + 1 end
			local exampleAttr = example and (' data-example-fulltype="' .. escapeHtml(example) .. '"') or ""
			emit('                  <div class="sik-taxonomy-leaf ' .. (example and "is-covered" or "is-uncovered")
				.. '" data-l1="' .. escapeHtml(l1) .. '" data-l2="' .. escapeHtml(l2) .. '"' .. exampleAttr .. '>')
			emit('                    <span class="sik-taxonomy-route">Destino L2</span>')
			emit('                    <span class="sik-taxonomy-example">' .. escapeHtml(example or "Sin ejemplo curado · GroundTruth v13") .. '</span>')
			emit("                  </div>")
		else
			for _, l3 in ipairs(l3s) do
				terminalCount = terminalCount + 1
				local example = examples[pathKey(l1, l2, l3)]
				if example then coveredCount = coveredCount + 1 end
				local exampleAttr = example and (' data-example-fulltype="' .. escapeHtml(example) .. '"') or ""
				emit('                  <div class="sik-taxonomy-leaf ' .. (example and "is-covered" or "is-uncovered")
					.. '" data-l1="' .. escapeHtml(l1) .. '" data-l2="' .. escapeHtml(l2) .. '" data-l3="' .. escapeHtml(l3) .. '"' .. exampleAttr .. '>')
				emit('                    <span class="sik-taxonomy-route"><strong>' .. escapeHtml(translated(l3))
					.. '</strong><code>' .. escapeHtml(l3) .. '</code></span>')
				emit('                    <span class="sik-taxonomy-example">' .. escapeHtml(example or "Sin ejemplo curado · GroundTruth v13") .. '</span>')
				emit("                  </div>")
			end
		end
		emit("                </div>")
		emit("              </section>")
	end
	emit("            </div>")
	emit("          </details>")
end

emit("        </div>")
emit("      </section>")
emit('      <footer class="sik-status-footer sik-taxonomy-footer">')
emit(string.format('        <span>%d familias · %d grupos · %d destinos</span><span>GroundTruth v%s · %d/%d con ejemplo</span>',
	#l1Order, l2Count, terminalCount, escapeHtml(GlobalStorageSiK.NativeTaxonomyGroundTruth.VERSION), coveredCount, terminalCount))
emit("      </footer>")
emit('      <span class="sik-resize-grip"></span>')
emit("    </section>")
emit("  </main>")
emit("</body>")
emit("</html>")

local rendered = table.concat(lines, "\n") .. "\n"
if arg and arg[1] == "--write" then
	local output = assert(io.open(OUTPUT, "wb"))
	output:write(rendered)
	output:close()
	print(string.format("generated %s: L1=%d L2=%d terminal=%d covered=%d",
		OUTPUT, #l1Order, l2Count, terminalCount, coveredCount))
else
	assert(readFile(OUTPUT) == rendered,
		"taxonomy HTML is stale; review the generated delta before running with --write")
	print(string.format("validated %s: L1=%d L2=%d terminal=%d covered=%d",
		OUTPUT, #l1Order, l2Count, terminalCount, coveredCount))
end
