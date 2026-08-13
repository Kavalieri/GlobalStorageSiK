--[[
	GlobalStorageSiK - Debug exhaustivo de la interfaz
	Autor: SiK
	Fecha: 2026-06-30
	Descripción: Registro completo de la pintada de la UI, clicks y acciones.
	             Todo gated por la opción sandbox DebugMode: al desactivarla,
	             cero salida y cero coste (cada helper hace early-return).
	             Salida en console.txt con prefijo [GS_UI].
]]

require "GS_Sandbox"

GlobalStorageSiK.UIDebug = GlobalStorageSiK.UIDebug or {}

--- ¿Debug de UI activo? Categoria propia (sandbox DebugModeUI), separada del
--- DebugMode general a proposito - ese inunda la consola con trazas de red
--- en cada comando y el rastro de clics/arbol de widgets se pierde entre el
--- ruido. Activar solo esta si lo que se investiga es clics/capas/layout.
---@return boolean
function GlobalStorageSiK.UIDebug.enabled()
	return GlobalStorageSiK.Sandbox ~= nil
		and GlobalStorageSiK.Sandbox.debugModeUI ~= nil
		and GlobalStorageSiK.Sandbox.debugModeUI() == true
end

local function out(line)
	print("[GS_UI] " .. line)
end

--- Log con formato (printf). No hace nada si el debug está desactivado.
---@param cat string
---@param msg string
function GlobalStorageSiK.UIDebug.log(cat, msg, ...)
	if not GlobalStorageSiK.UIDebug.enabled() then return end
	local text = msg
	if select("#", ...) > 0 then
		local ok, f = pcall(string.format, msg, ...)
		if ok then text = f end
	end
	out(tostring(cat) .. " > " .. tostring(text))
end

--- Recoge nombres de campos (string) que apuntan a elementos UI, para etiquetar el árbol.
---@param map table
---@param t table|nil
local function collectNames(map, t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do
		if type(k) == "string" and type(v) == "table" and not map[v] then
			local isWidget = false
			pcall(function() isWidget = (v.getX ~= nil and v.getWidth ~= nil) end)
			if isWidget then map[v] = k end
		end
	end
end

--- Vuelca el árbol completo de elementos visibles/ocultos bajo root.
--- Recorre childrenInOrder (el array real de PZ; children es hash por ID).
--- Detecta solapes (misma x/y) y duplicados (mismo nombre repetido) a simple vista.
---@param root table|nil  raíz (normalmente el GS_TerminalUI)
---@param label string
function GlobalStorageSiK.UIDebug.dumpTree(root, label)
	if not GlobalStorageSiK.UIDebug.enabled() or not root then return end
	local nameMap = {}
	collectNames(nameMap, root)
	collectNames(nameMap, root.contentHost)
	collectNames(nameMap, root.networkPanel)
	collectNames(nameMap, root.itemsPanel)
	out("===== TREE [" .. tostring(label) .. "] =====")
	local count = 0
	local seenPos = {}
	local function walk(el, depth)
		if type(el) ~= "table" or count > 600 then return end
		count = count + 1
		local vis = "?"
		pcall(function() vis = (el.isVisible and el:isVisible()) and "V" or "." end)
		local x, y, w, h = -1, -1, -1, -1
		pcall(function() x, y, w, h = el:getX(), el:getY(), el:getWidth(), el:getHeight() end)
		local name = nameMap[el] or el._gsDebugName or "?"
		local flag = ""
		-- marcar posibles solapes: mismo nombre visible repetido en mismo padre-depth
		local key = tostring(name) .. "@" .. tostring(depth)
		if vis == "V" and name ~= "?" then
			if seenPos[key] then flag = "  <<DUP?" else seenPos[key] = true end
		end
		out(string.format("%s[%s] %-22s x=%d y=%d w=%d h=%d%s",
			string.rep("  ", depth), vis, tostring(name), x, y, w, h, flag))
		local ch = el.childrenInOrder
		if type(ch) == "table" then
			for i = 1, #ch do walk(ch[i], depth + 1) end
		end
	end
	walk(root, 0)
	out("===== /TREE " .. tostring(count) .. " elementos =====")
end

--- Rectángulos: solape parcial (no contención total, que es anidamiento legítimo).
local function rectsOverlap(a, b)
	if not (a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h) then
		return false
	end
	local function contains(p, q)
		return p.x <= q.x and p.y <= q.y and (p.x + p.w) >= (q.x + q.w) and (p.y + p.h) >= (q.y + q.h)
	end
	-- Contención total = wrapper/anidamiento, no es "pisar". Solo reportamos solape parcial.
	if contains(a, b) or contains(b, a) then return false end
	return true
end

local function measureRect(el)
	local x, y, w, h = 0, 0, 0, 0
	pcall(function() x, y, w, h = el:getX(), el:getY(), el:getWidth(), el:getHeight() end)
	return { x = x, y = y, w = w, h = h }
end

local function isVisibleEl(el)
	local v = false
	pcall(function() v = (not el.isVisible) or el:isVisible() end)
	return v
end

local function isScrollBar(el)
	local ok, r = pcall(function()
		return GlobalStorageSiK.TerminalScroll
			and GlobalStorageSiK.TerminalScroll.isNeatScrollBar
			and GlobalStorageSiK.TerminalScroll.isNeatScrollBar(el)
	end)
	return ok and r == true
end

--- Recorre el árbol y reporta SOLO solapes parciales entre hermanos visibles.
--- Es la verificación objetiva de "ningún elemento pisa al anterior".
---@param root table|nil
---@param label string
function GlobalStorageSiK.UIDebug.checkOverlaps(root, label)
	if not GlobalStorageSiK.UIDebug.enabled() or not root then return end
	local nameMap = {}
	collectNames(nameMap, root)
	collectNames(nameMap, root.contentHost)
	collectNames(nameMap, root.networkPanel)
	collectNames(nameMap, root.itemsPanel)
	local function nameOf(el) return nameMap[el] or el._gsDebugName or "?" end
	local total = 0
	local function walk(el)
		local ch = el.childrenInOrder
		if type(ch) ~= "table" then return end
		local vis = {}
		for i = 1, #ch do
			local c = ch[i]
			if c and isVisibleEl(c) and not isScrollBar(c) then
				local r = measureRect(c)
				if r.w > 0 and r.h > 0 then
					vis[#vis + 1] = { el = c, r = r }
				end
			end
		end
		for i = 1, #vis do
			for j = i + 1, #vis do
				if rectsOverlap(vis[i].r, vis[j].r) then
					total = total + 1
					out(string.format("SOLAPE > %s: %s (%d,%d %dx%d) ∩ %s (%d,%d %dx%d)",
						tostring(label),
						nameOf(vis[i].el), vis[i].r.x, vis[i].r.y, vis[i].r.w, vis[i].r.h,
						nameOf(vis[j].el), vis[j].r.x, vis[j].r.y, vis[j].r.w, vis[j].r.h))
				end
			end
		end
		for i = 1, #ch do walk(ch[i]) end
	end
	walk(root)
	if total == 0 then
		out("OVERLAP-CHECK [" .. tostring(label) .. "] OK — 0 solapes")
	else
		out("OVERLAP-CHECK [" .. tostring(label) .. "] *** " .. total .. " SOLAPE(S) ***")
	end
end

--- Envuelve un callback onClick para registrar la acción antes de ejecutarla.
--- Devuelve el callback original intacto si el debug está desactivado en runtime
--- (la comprobación se hace dentro, así no hay coste).
---@param label string
---@param onClick function|nil
---@return function|nil
function GlobalStorageSiK.UIDebug.wrapClick(label, onClick)
	if onClick == nil then return nil end
	return function(target, ...)
		if GlobalStorageSiK.UIDebug.enabled() then
			out("CLICK > " .. tostring(label))
		end
		return onClick(target, ...)
	end
end

--- Registra una acción puntual (cambio de combo, selección, drag, etc.).
---@param what string
---@param detail any|nil
function GlobalStorageSiK.UIDebug.action(what, detail)
	if not GlobalStorageSiK.UIDebug.enabled() then return end
	if detail ~= nil then
		out("ACTION > " .. tostring(what) .. " | " .. tostring(detail))
	else
		out("ACTION > " .. tostring(what))
	end
end
