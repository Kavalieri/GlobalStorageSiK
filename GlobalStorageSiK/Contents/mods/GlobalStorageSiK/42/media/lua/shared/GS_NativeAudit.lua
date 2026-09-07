--[[
	GlobalStorageSiK - Auditoria minima del catalogo nativo
	Autor: SiK
	Fecha: 2026-08-27

	Herramienta DEV/admin explicita (§8.1, §11 del documento) - NUNCA se
	ejecuta automaticamente en el arranque normal. Recorre getAllItems() UNA
	vez, ejercita el contrato + registro reales (NativeClassifier.classify,
	NativeTaxonomyRegistry.hasL1/hasL2/hasL3) y detecta fallos estructurales
	ANTES de que el primer bloque de clasificacion (Combate) los convierta en
	cientos de entradas cacheadas incorrectas.

	Pedido explicito del equipo de sistemas: auditor tecnico minimo, no una
	interfaz grande. Solo cuenta/detecta/mide; no corrige nada por su cuenta.
]]

require "GS_CatalogManager"
require "GS_NativeTaxonomyRegistry"
require "GS_NativeClassifier"
require "GSSiK_API"
require "GS_NativeClassifierUtils"

GlobalStorageSiK.NativeAudit = GlobalStorageSiK.NativeAudit or {}

local MAX_SAMPLES_PER_BUCKET = 20
-- Pedido explicito del equipo de sistemas (2026-08-27, revision de dev4):
-- "como minimo, muestras de 50-100 objetos para cada heuristica debil" - las
-- reglas de Materiales basadas en nombre (name_wood/name_textile/...)
-- necesitan mas muestra que el resto para poder revisar falsos positivos de
-- verdad, no solo confirmar que existen.
local MAX_SAMPLES_WEAK_SOURCE = 80
local WEAK_SOURCES = {
	name_wood = true, name_textile = true, name_leather = true,
	name_mineral = true, name_organic = true,
}

-- Pedido explicito del equipo de sistemas (2026-08-27, revision de dev6):
-- "la presencia de otros tipos como ZedDmg_BACK_Slash y FISH_DEV_ITEM
-- demuestra que la auditoria recorre tambien objetos internos o de
-- desarrollo" - SIN un getter confirmado en ScriptItem para distinguir
-- "es un item real jugable" de "es un proxy interno/de desarrollo del
-- motor" (no se encontro ninguno revisando la Lua API del juego), esto es
-- SOLO un contador diagnostico por nombre - nunca decide nada en
-- NativeClassifier, nunca excluye nada de la clasificacion real. Es una
-- pista para que sistemas revise la muestra, no una clasificacion.
local INTERNAL_OR_DEBUG_TOKENS = {
	zed = true, dmg = true, dev = true, debug = true, test = true, unused = true,
}
local MAX_SAMPLES_INTERNAL_OR_DEBUG = 40

-- Exclusiones internas con frontera estructural confirmada. Nunca se usan
-- palabras del nombre: un objeto jugable que contenga "bone"/"debug" no
-- queda oculto por accidente. `base:wound` son proxies anatómicos del motor,
-- no objetos obtenibles; el censo DEV32.3 los separa de los ítems visibles
-- antes de exigir cobertura completa de éstos.
local INTERNAL_EXCLUSION_BODY_LOCATIONS = {
	["base:zeddmg"] = "body_location_zeddmg",
	["base:wound"] = "body_location_wound",
}

---@param si table|nil
---@return string|nil reason
local function internalExclusionReason(si)
	return INTERNAL_EXCLUSION_BODY_LOCATIONS[GlobalStorageSiK.NativeClassifierUtils.bodyLocationLower(si)]
end

-- Probes controlados pedidos por sistemas (dev13, informe sobre dev12):
-- "hace falta un probe especifico que registre para estos objetos getters,
-- tags y propiedades" - SOLO diagnostico, nunca decide nada en
-- NativeClassifier. Dos listas curadas a mano de fullTypes reales donde ya
-- se confirmo la ambiguedad/duda concreta:
-- 1. Alimentos vs. Conocimiento (PizzaRecipe/RecipeClipping...) - el sufijo
--    "Recipe" no basta para saber si es comida real o una entidad interna.
-- 2. Contenedor de liquido real vs. nombre que solo menciona un envase
--    (BottleOpener no es un contenedor) - se investiga si el ScriptItem
--    estatico expone alguna señal fiable mas alla del nombre.
local FOOD_RECIPE_PROBE_FULLTYPES = {
	["Base.PizzaRecipe"] = true, ["Base.BurgerRecipe"] = true,
	["Base.OmeletteRecipe"] = true, ["Base.OmeletteRecipeForged"] = true,
	["Base.PotOfSoupRecipe"] = true, ["Base.RecipeClipping"] = true,
}
local FLUID_CONTAINER_PROBE_FULLTYPES = {
	["Base.BottleOpener"] = true, ["Base.BottleOpener_Keychain"] = true,
	["Base.JarLid"] = true, ["Base.CookieJar"] = true,
	["Base.Bucket"] = true, ["Base.BucketWaterDebug"] = true,
	["Base.WaterBottleFull"] = true, ["Base.Canteen"] = true,
}
-- dev15: los metodos candidato de dev13 (getFluidContainer/isFluidContainer/
-- getCapacity/isWaterSource) quedaron descartados - sistemas confirmo via
-- javap que la señal real es `containsComponent(ComponentType.FluidContainer)`,
-- ya expuesta como GlobalStorageSiK.NativeClassifierUtils.hasFluidContainerComponent().

-- dev19: probe pedido por sistemas en la validacion de dev18 - "el codigo
-- efectivo es correcto, pero el fichero solo prueba las rutas y recuentos,
-- no imprime attributes.tier/attributes.variant" - cierra la verificacion
-- extremo a extremo (dispatcher -> cache -> ClassificationResult final) para
-- los 7 objetos afectados, con el valor ESPERADO fijado a mano (ver
-- GS_NativeClassifierOwnItems.lua, tabla EXACT) frente al OBSERVADO real.
local TIER_VARIANT_PROBE_EXPECTED = {
	["GSSiK_Addon_Tablet.GS_WifiChip_T1"] = { tier = "1" },
	["GSSiK_Addon_Tablet.GS_WifiChip_T2"] = { tier = "2" },
	["GSSiK_Addon_Tablet.GS_WifiChip_T3"] = { tier = "3" },
	["GSSiK_Addon_Tablet.GS_Tablet"] = { variant = "base" },
	["GSSiK_Addon_Tablet.GS_TabletCraft"] = { variant = "craft" },
	["GSSiK_Addon_Tablet.GS_TabletBuilder"] = { variant = "builder" },
	["GSSiK_Addon_Tablet.GS_TabletMaster"] = { variant = "master" },
}

---@param list table
---@param value string
---@param limit number|nil
local function addSample(list, value, limit)
	if #list < (limit or MAX_SAMPLES_PER_BUCKET) then
		list[#list + 1] = value
	end
end

-- Censo completo DEV32.3: una fila por ScriptItem recorrido. Es evidencia de
-- servidor para decidir cobertura; no alimenta la UI ni altera el resultado
-- del clasificador. La ruta nativa sigue siendo la unica autoridad.
---@param report table
---@param fullType string
---@param outcome string
---@param path table|nil
---@param evidence table|nil
---@param reason string|nil
---@param si table|nil
local function addCensusRecord(report, fullType, outcome, path, evidence, reason, si)
	local primary = evidence and evidence.primary
	path = path or {}
	report.censusInventory[#report.censusInventory + 1] = {
		fullType = fullType,
		outcome = outcome,
		l1 = path.l1 or "",
		l2 = path.l2 or "",
		l3 = path.l3 or "",
		source = (primary and primary.source) or "",
		confidence = (primary and primary.confidence) or "",
		reason = reason or "",
		bodyLocation = GlobalStorageSiK.NativeClassifierUtils.bodyLocation(si),
	}
end

--- Ejecuta la auditoria completa. Debe llamarse explicitamente (comando de
--- debug/consola de admin) - nunca desde OnGameBoot ni ningun otro evento
--- automatico.
---@return table report
function GlobalStorageSiK.NativeAudit.run()
	local report = {
		ranAt = (getTimestampMs and getTimestampMs()) or 0,
		ready = GlobalStorageSiK.CatalogManager.isReady(),
		sealed = GlobalStorageSiK.NativeClassifier.isSealed(),
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
		-- dev23 (pedido explicito de sistemas: "digest corto + modCount +
		-- build para UI, fingerprint completo solo en el fichero") - el
		-- informe de texto sigue llevando el fingerprint completo de arriba,
		-- estos 3 campos son solo para que un consumidor (la pestaña
		-- Taxonomia) no tenga que parsear esa cadena larga.
		catalogFingerprintDigest = GlobalStorageSiK.CatalogManager.getCatalogFingerprintDigest(),
		activeModCount = GlobalStorageSiK.CatalogManager.getActiveModCount(),
		gameBuildVersion = GlobalStorageSiK.CatalogManager.getGameBuildVersion(),
		totalTypes = 0,
		classified = 0,
		classifiedByL1 = {},        -- l1 -> contador (== coverageByL1)
		coverageBySource = {},      -- evidence.primary.source -> contador
		coverageByConfidence = {},  -- confidence numerica -> contador
		pending = 0,
		unclassified = 0,           -- other/unclassified_modded
		excludedInternal = 0,       -- unclassified con señal interna estructural aprobada
		excludedInternalByReason = {},
		invalidPath = 0,            -- l1/l2/l3 no registrados en GS_NativeTaxonomyRegistry
		classifierErrors = 0,       -- pcall del bloque fallo (ver GS_NativeClassifier.computeClassification)
		precedenceCollisions = {},  -- { fullType, winner={l1,l2,l3}, others={{blockIndex,path},...} }
		ownItems = {
			expectedExactMappings = 0,
			foundExactMappings = 0,
			missingExactMappings = {},   -- registrados en EXACT pero AUSENTES del catalogo real (typo/renombrado)
			ownModuleTypesUnmapped = {}, -- modulos/discos reales de AddonRegistry que NO estan en la tabla EXACT
		},
		samples = {
			pending = {},
			unclassified = {},
			invalidPath = {},
			classifierErrors = {},
			bySource = {},           -- source -> lista de "fullType -> l1/l2/l3"
			likelyInternalOrDebug = {}, -- diagnostico por nombre, ver INTERNAL_OR_DEBUG_TOKENS
			firearmOtherProbe = {},    -- combat/firearm/other: valor crudo de isTwoHandWeapon(), pedido de sistemas
			foodRecipeProbe = {},      -- dev13: Alimentos vs. Conocimiento (PizzaRecipe...), pedido de sistemas
			fluidContainerProbe = {},  -- dev13: contenedor de liquido real vs. nombre (BottleOpener...), pedido de sistemas
			debugOnly = {},            -- dev15: muestra de fullType con isDebugOnly()==true real, pedido de sistemas
			tierVariantProbe = {},     -- dev19: attributes.tier/variant observado vs. esperado, pedido de sistemas
		},
		debugOnlyCount = 0,
		-- dev13 (pedido explicito de sistemas): inventario completo de lo sin
		-- clasificar - SOLO se escribe a fichero aparte
		-- (GlobalStorageSiK_NativeAudit_Unclassified.tsv), nunca se envia por
		-- red ni se muestra en la UI (ver GS_Server.lua).
		unclassifiedInventory = {},
		excludedInternalInventory = {},
		censusInventory = {},        -- una fila por fullType, solo fichero server-side DEV32.3
		tokenFrequency = {},
		moduleFrequency = {},
		likelyInternalOrDebugCount = 0,
		timeMs = 0,
		queried = 0,
	}

	-- BUG REAL evitado a proposito (mismo motivo que §8.1): auditar antes de
	-- ready/sealed no tiene sentido - devolveria "pending" para todo. Se
	-- informa del estado y se corta aqui, sin fingir un resultado completo.
	if not report.ready or not report.sealed then
		report.aborted = true
		report.abortReason = not report.ready and "catalog_not_ready" or "blocks_not_sealed"
		return report
	end

	if not getAllItems then
		report.aborted = true
		report.abortReason = "getAllItems_unavailable"
		return report
	end

	local startMs = (getTimestampMs and getTimestampMs()) or 0
	local ok, items = pcall(getAllItems)
	if not ok or not items then
		report.aborted = true
		report.abortReason = "getAllItems_failed"
		return report
	end

	local total = items:size()
	local catalogFullTypes = {}
	for i = 0, total - 1 do
		local si = items:get(i)
		local fullType = nil
		local okFt, ft = pcall(function() return si:getFullName() end)
		if okFt and ft then
			fullType = ft
		end
		if fullType then
			catalogFullTypes[fullType] = true
			report.totalTypes = report.totalTypes + 1
			report.queried = report.queried + 1

			local nameTokens = GlobalStorageSiK.NativeClassifierUtils.tokenize(
				GlobalStorageSiK.NativeClassifierUtils.typeName(si))
			for ti = 1, #nameTokens do
				if INTERNAL_OR_DEBUG_TOKENS[nameTokens[ti]] then
					report.likelyInternalOrDebugCount = report.likelyInternalOrDebugCount + 1
					addSample(report.samples.likelyInternalOrDebug, fullType, MAX_SAMPLES_INTERNAL_OR_DEBUG)
					break
				end
			end

			local result = GlobalStorageSiK.NativeClassifier.classify(fullType)

			-- dev15 (hallazgo de sistemas sobre dev14): "isDebugOnly(): API
			-- valida, resultado aun no demostrado - no aparece una fuente
			-- especifica script_debug_only... no debe afirmarse que el
			-- catalogo interno quedo filtrado hasta obtener esa evidencia".
			-- Contador y muestra EXPLICITOS, independientes de si el bloque
			-- resultante los reclamo o no - para responder sin ambiguedad
			-- "¿isDebugOnly() devolvio true para algo, o nunca lo hace?".
			if si.isDebugOnly then
				local okDebugOnly, isDebugOnlyValue = pcall(function() return si:isDebugOnly() end)
				if okDebugOnly and isDebugOnlyValue == true then
					report.debugOnlyCount = report.debugOnlyCount + 1
					addSample(report.samples.debugOnly, fullType, MAX_SAMPLES_INTERNAL_OR_DEBUG)
				end
			end

			-- Probes controlados de sistemas (dev13, actualizados dev15 tras
			-- "el probe de fluidos todavia imprime campos antiguos... deberia
			-- mostrar exactamente la señal que decide"): itemTypeRaw real,
			-- hasFluidContainerComponent real, isDebugOnly real, bloque
			-- ganador Y bloques alternativos (via diagnosticClassifyAllBlocks,
			-- mismo mecanismo que las colisiones de precedencia normales).
			if FOOD_RECIPE_PROBE_FULLTYPES[fullType] or FLUID_CONTAINER_PROBE_FULLTYPES[fullType] then
				local path = result and result.primaryPath or {}
				local itemTypeRaw = GlobalStorageSiK.NativeClassifierUtils.itemTypeLower(si)
				local hasFluid = GlobalStorageSiK.NativeClassifierUtils.hasFluidContainerComponent(si)
				local isDebugOnlyRaw = "?"
				if si.isDebugOnly then
					local okD, vD = pcall(function() return si:isDebugOnly() end)
					isDebugOnlyRaw = okD and tostring(vD) or "error"
				end
				local allClaims = GlobalStorageSiK.NativeClassifier.diagnosticClassifyAllBlocks(fullType)
				local alternates = {}
				for ci = 1, #allClaims do
					local cp = allClaims[ci].primaryPath or {}
					if cp.l1 ~= path.l1 or cp.l2 ~= path.l2 or cp.l3 ~= path.l3 then
						alternates[#alternates + 1] = allClaims[ci].blockName .. ":" .. tostring(cp.l1) .. "/" .. tostring(cp.l2) .. "/" .. tostring(cp.l3)
					end
				end
				local line = fullType .. " -> " .. tostring(path.l1) .. "/" .. tostring(path.l2) .. "/" .. tostring(path.l3)
					.. " itemTypeRaw=" .. itemTypeRaw .. " hasFluidContainerComponent=" .. tostring(hasFluid)
					.. " isDebugOnly=" .. isDebugOnlyRaw
					.. " alternates=[" .. table.concat(alternates, ", ") .. "]"
				if FOOD_RECIPE_PROBE_FULLTYPES[fullType] then
					addSample(report.samples.foodRecipeProbe, line, MAX_SAMPLES_WEAK_SOURCE)
				end
				if FLUID_CONTAINER_PROBE_FULLTYPES[fullType] then
					addSample(report.samples.fluidContainerProbe, line, MAX_SAMPLES_WEAK_SOURCE)
				end
			end

			local tierVariantExpected = TIER_VARIANT_PROBE_EXPECTED[fullType]
			if tierVariantExpected then
				local path = result and result.primaryPath or {}
				local attrs = result and result.attributes or {}
				local observedTier = attrs.tier
				local observedVariant = attrs.variant
				local expectedTier = tierVariantExpected.tier
				local expectedVariant = tierVariantExpected.variant
				local match = (expectedTier == nil or expectedTier == observedTier)
					and (expectedVariant == nil or expectedVariant == observedVariant)
				local primaryEvidence = result and result.evidence and result.evidence.primary
				local source = (primaryEvidence and primaryEvidence.source) or "?"
				addSample(report.samples.tierVariantProbe,
					fullType .. " -> " .. tostring(path.l1) .. "/" .. tostring(path.l2) .. "/" .. tostring(path.l3)
						.. " tier(observado=" .. tostring(observedTier) .. ", esperado=" .. tostring(expectedTier) .. ")"
						.. " variant(observado=" .. tostring(observedVariant) .. ", esperado=" .. tostring(expectedVariant) .. ")"
						.. " source=" .. source
						.. " match=" .. tostring(match))
			end

			if not result then
				-- fullType invalido segun classify() - no deberia pasar
				-- viniendo de getAllItems(), pero se cuenta como error
				-- estructural si ocurre.
				report.classifierErrors = report.classifierErrors + 1
				addCensusRecord(report, fullType, "classifier_error", nil, nil, "missing_result", si)
			elseif result.pending then
				report.pending = report.pending + 1
				addSample(report.samples.pending, fullType)
				addCensusRecord(report, fullType, "pending", result.primaryPath, result.evidence, "catalog_pending", si)
			elseif result.classifierError then
				-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de
				-- sistemas): antes una excepcion real dentro de un bloque
				-- terminaba indistinguible de "unclassified_modded" - ahora
				-- computeClassification() la marca explicitamente
				-- (result.classifierError) y el auditor la cuenta/muestrea
				-- aparte, con el mensaje real del bloque que fallo.
				report.classifierErrors = report.classifierErrors + 1
				local reasons = result.evidence and result.evidence.conflicting
				addSample(report.samples.classifierErrors,
					fullType .. (reasons and (" -> " .. table.concat(reasons, " | ")) or ""))
				addCensusRecord(report, fullType, "classifier_error", result.primaryPath, result.evidence,
					"classifier_error", si)
			else
				local path = result.primaryPath or {}
				local l1, l2, l3 = path.l1, path.l2, path.l3
				-- coverageBySource / coverageByConfidence / samplesBySourceAndPath
				-- (pedido explicito del equipo de sistemas tras revisar dev4:
				-- "el informe no permite validar la precision" - sin esto, un
				-- 88% de cobertura via heuristicas debiles de nombre quedaba
				-- indistinguible de cobertura via tags oficiales de alta
				-- confianza).
				local primaryEvidence = result.evidence and result.evidence.primary
				local source = (primaryEvidence and primaryEvidence.source) or "?"
				local confidence = (primaryEvidence and primaryEvidence.confidence) or 0
				report.coverageBySource[source] = (report.coverageBySource[source] or 0) + 1
				report.coverageByConfidence[confidence] = (report.coverageByConfidence[confidence] or 0) + 1

				-- Probe controlado pedido por sistemas (dev10): muestra real
				-- de armas de fuego sin subtipo, con el valor CRUDO de
				-- isTwoHandWeapon() (incluido "nil" tal cual) - para decidir
				-- si es un limite real de la API sobre el ScriptItem estatico
				-- o si falta una señal distinta. Nunca decide clasificacion.
				if l1 == "combat" and l2 == "firearm" and l3 == "other" then
					local rawTwoHand = result.attributes and result.attributes.twoHandRaw
					local rawAmmo = result.attributes and result.attributes.ammoType
					addSample(report.samples.firearmOtherProbe,
						fullType .. " -> isTwoHandWeapon()=" .. tostring(rawTwoHand) .. " ammoType=" .. tostring(rawAmmo),
						MAX_SAMPLES_WEAK_SOURCE)
				end

				if not (l1 == "other" and l2 == "unclassified_modded") then
					local limit = WEAK_SOURCES[source] and MAX_SAMPLES_WEAK_SOURCE or MAX_SAMPLES_PER_BUCKET
					report.samples.bySource[source] = report.samples.bySource[source] or {}
					addSample(report.samples.bySource[source],
						fullType .. " -> " .. tostring(l1) .. "/" .. tostring(l2) .. "/" .. tostring(l3), limit)

					-- Colisiones de precedencia (pedido explicito): solo se
					-- comprueba para tipos YA clasificados (si nadie lo
					-- reclamo, no puede haber colision por definicion) - mas
					-- caro que classify() normal (prueba TODOS los bloques,
					-- sin cache), aceptable como coste puntual de auditoria.
					local allClaims = GlobalStorageSiK.NativeClassifier.diagnosticClassifyAllBlocks(fullType)
					if #allClaims > 1 then
						local others = {}
						for ci = 1, #allClaims do
							local claim = allClaims[ci]
							local cp = claim.primaryPath or {}
							if cp.l1 ~= l1 or cp.l2 ~= l2 or cp.l3 ~= l3 then
								others[#others + 1] = string.format("%s:%s/%s/%s",
									tostring(claim.blockName), tostring(cp.l1), tostring(cp.l2), tostring(cp.l3))
							end
						end
						if #others > 0 then
							addSample(report.precedenceCollisions,
								fullType .. " -> gano " .. l1 .. "/" .. tostring(l2) .. "/" .. tostring(l3)
									.. " | tambien reclamado por " .. table.concat(others, ", "),
								MAX_SAMPLES_WEAK_SOURCE)
						end
					end
				end

				if l1 == "other" and l2 == "unclassified_modded" then
					local exclusionReason = internalExclusionReason(si)
					if exclusionReason then
						report.excludedInternal = report.excludedInternal + 1
						report.excludedInternalByReason[exclusionReason] =
							(report.excludedInternalByReason[exclusionReason] or 0) + 1
						report.excludedInternalInventory[#report.excludedInternalInventory + 1] = {
							fullType = fullType,
							reason = exclusionReason,
							bodyLocation = GlobalStorageSiK.NativeClassifierUtils.bodyLocationLower(si),
						}
						addCensusRecord(report, fullType, "excluded_internal", path, result.evidence, exclusionReason, si)
					else
						report.unclassified = report.unclassified + 1
						addSample(report.samples.unclassified, fullType)

						-- Pedido explicito del equipo de sistemas (dev13, tras
					-- revisar dev11): "una muestra de 20 entre 2540 no basta
					-- para decidir el siguiente bloque cuantitativamente" -
					-- inventario COMPLETO de lo sin clasificar, solo a
					-- fichero (ver writeUnclassifiedTsv), NUNCA por red ni en
					-- la UI - ver GS_Server.lua, el cliente solo recibe el
					-- resumen de siempre.
					local module = fullType:match("^([^.]+)%.") or "?"
					report.moduleFrequency[module] = (report.moduleFrequency[module] or 0) + 1
					local typeName = GlobalStorageSiK.NativeClassifierUtils.typeName(si)
					local nameTokens2 = GlobalStorageSiK.NativeClassifierUtils.tokenize(typeName)
					for ti = 1, #nameTokens2 do
						report.tokenFrequency[nameTokens2[ti]] = (report.tokenFrequency[nameTokens2[ti]] or 0) + 1
					end
					local bodyLoc = GlobalStorageSiK.NativeClassifierUtils.bodyLocation(si)
					local wcStr = ""
					local wc = GlobalStorageSiK.NativeClassifierUtils.getWeaponCategories(si)
					if wc then
						wcStr = GlobalStorageSiK.NativeClassifierUtils.safeCall(function() return tostring(wc) end) or ""
					end
					local ammoTypeRaw = si.getAmmoType and GlobalStorageSiK.NativeClassifierUtils.safeCall(function() return si:getAmmoType() end)
						report.unclassifiedInventory[#report.unclassifiedInventory + 1] = {
						fullType = fullType,
						module = module,
						typeName = typeName,
						bodyLocation = bodyLoc,
						weaponCategories = wcStr,
						ammoType = ammoTypeRaw and tostring(ammoTypeRaw) or "",
						tokens = table.concat(nameTokens2, " "),
						}
						addCensusRecord(report, fullType, "unclassified", path, result.evidence, "no_native_rule", si)
					end
				else
					report.classified = report.classified + 1
					report.classifiedByL1[l1 or "?"] = (report.classifiedByL1[l1 or "?"] or 0) + 1
				end
				-- Valida la ruta contra el registro real - detecta un
				-- clasificador de bloque que devuelva una clave inventada,
				-- mal escrita, o una estructura L3 que hasL3() no reconozca
				-- (mismo bug real ya cerrado para globalstoragesik.peripheral).
				-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de
				-- sistemas): el fallback "#L3==0 => vale cualquier L3" (aqui
				-- mismo) autorizaba sin querer L3 inventados en cualquier
				-- grupo aun sin poblar - la excepcion real (L3 dinamico) se
				-- declara ahora EXPLICITAMENTE en el registro
				-- (isDynamicL3), hasL3() ya la aplica por si sola - este
				-- auditor solo necesita llamarla, sin logica propia.
				local pathOk = GlobalStorageSiK.NativeTaxonomyRegistry.hasL1(l1)
				if pathOk and l2 then
					pathOk = GlobalStorageSiK.NativeTaxonomyRegistry.hasL2(l1, l2)
				end
				if pathOk and l2 and l3 then
					pathOk = GlobalStorageSiK.NativeTaxonomyRegistry.hasL3(l1, l2, l3)
				end
				if not pathOk then
					report.invalidPath = report.invalidPath + 1
					addSample(report.samples.invalidPath,
						fullType .. " -> " .. tostring(l1) .. "/" .. tostring(l2) .. "/" .. tostring(l3))
				end
				if not (l1 == "other" and l2 == "unclassified_modded") then
					addCensusRecord(report, fullType, pathOk and "classified" or "invalid_path", path,
						result.evidence, pathOk and nil or "taxonomy_registry_rejected", si)
				end
			end
		end
	end
	report.reconciledTotal = report.classified + report.unclassified + report.excludedInternal
		+ report.pending + report.classifierErrors
	report.reconciliationDelta = report.totalTypes - report.reconciledTotal
	table.sort(report.excludedInternalInventory, function(a, b) return a.fullType < b.fullType end)
	table.sort(report.censusInventory, function(a, b) return a.fullType < b.fullType end)
	-- Diff de mapeos exactos del grupo 14 (pedido explicito): compara la
	-- tabla EXACT de GS_NativeClassifierOwnItems.lua contra el catalogo REAL
	-- ya recorrido, y contra los modulos/discos que AddonRegistry dice que
	-- existen de verdad - detecta un fullType renombrado (registrado pero
	-- ausente del catalogo real) o un modulo/disco nuevo sin dar de alta en
	-- la tabla EXACT.
	if GlobalStorageSiK.NativeClassifier.getOwnItemsExactTable then
		local exact = GlobalStorageSiK.NativeClassifier.getOwnItemsExactTable()
		local exactCount = 0
		local foundCount = 0
		for fullType in pairs(exact) do
			exactCount = exactCount + 1
			if catalogFullTypes[fullType] then
				foundCount = foundCount + 1
			else
				addSample(report.ownItems.missingExactMappings, fullType, MAX_SAMPLES_WEAK_SOURCE)
			end
		end
		report.ownItems.expectedExactMappings = exactCount
		report.ownItems.foundExactMappings = foundCount

		local listed, _, defs = GSSiK.API.Addon.list()
		if listed then
			for i = 1, #defs do
				local def = defs[i]
				local typesOk, _, moduleTypes = GSSiK.API.Addon.moduleItemTypes(def.id)
				if not typesOk then moduleTypes = {} end
				for j = 1, #moduleTypes do
					local ft = moduleTypes[j]
					if ft and ft ~= "" and not exact[ft] then
						addSample(report.ownItems.ownModuleTypesUnmapped, ft .. " (modulo de " .. tostring(def.id) .. ")", MAX_SAMPLES_WEAK_SOURCE)
					end
				end
				if def.installDiskItem and def.installDiskItem ~= "" and not exact[def.installDiskItem] then
					addSample(report.ownItems.ownModuleTypesUnmapped, def.installDiskItem .. " (disco de " .. tostring(def.id) .. ")", MAX_SAMPLES_WEAK_SOURCE)
				end
			end
		end
	end

	report.timeMs = ((getTimestampMs and getTimestampMs()) or 0) - startMs

	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("NativeAudit",
			string.format(
				"auditoria: total=%d classified=%d pending=%d unclassified=%d excludedInternal=%d invalidPath=%d classifierErrors=%d delta=%d tiempo=%dms",
				report.totalTypes, report.classified, report.pending, report.unclassified, report.excludedInternal,
				report.invalidPath, report.classifierErrors, report.reconciliationDelta, report.timeMs))
	end
	return report
end

local REPORT_FILE_NAME = "GlobalStorageSiK_NativeAudit.log"
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev13): con
-- tsvCell() ya evitando cualquier nil, el fichero SEGUÍA sin crearse -
-- diagnóstico repetible: "getFileWriter_failed" antes de escribir la
-- cabecera. B42.20.4 aplica restricciones de seguridad sobre la EXTENSIÓN
-- del nombre y rechaza ".tsv" - el mismo API/carpeta/proceso ya funciona
-- con ".log" (GlobalStorageSiK_NativeAudit.log). Contenido sigue siendo
-- tabulado (TSV real), solo cambia la extensión admitida.
local UNCLASSIFIED_TSV_NAME = "GlobalStorageSiK_NativeAudit_Unclassified.log"
local CENSUS_TSV_NAME = "GlobalStorageSiK_NativeAudit_Census.log"

---@param n number|nil
---@return string
local function fmt(n)
	return tostring(n or 0)
end

--- Escribe el informe COMPLETO (incluidas las muestras) en la ruta única de
--- `report.diagnosticReportFile`, asignada por DiagnosticsSession bajo
--- Lua/SiKDiagnostics/GlobalStorageSiK/<sessionId>/taxonomy/. `append=false`
--- solo inicializa ese runId nuevo: nunca sustituye otra ejecución.
---@param report table
function GlobalStorageSiK.NativeAudit.writeReportToFile(report)
	if not getFileWriter then
		return false
	end
	local fileName = (report and report.diagnosticReportFile) or REPORT_FILE_NAME
	local ok, writer = pcall(getFileWriter, fileName, true, false)
	if not ok or not writer then
		return false
	end
	local okWrite = pcall(function()
		writer:write("=== GlobalStorageSiK NativeAudit ===\r\n")
		if report.aborted then
			writer:write("ABORTADO: " .. tostring(report.abortReason) .. "\r\n")
			writer:close()
			return
		end
		writer:write("epoch=" .. fmt(report.catalogEpoch) .. " fingerprint=" .. tostring(report.catalogFingerprint) .. "\r\n")
		writer:write("totalTypes=" .. fmt(report.totalTypes) .. " classified=" .. fmt(report.classified)
			.. " pending=" .. fmt(report.pending) .. " unclassified=" .. fmt(report.unclassified)
			.. " excludedInternal=" .. fmt(report.excludedInternal) .. " invalidPath=" .. fmt(report.invalidPath)
			.. " classifierErrors=" .. fmt(report.classifierErrors) .. " reconciledTotal=" .. fmt(report.reconciledTotal)
			.. " reconciliationDelta=" .. fmt(report.reconciliationDelta) .. " tiempoMs=" .. fmt(report.timeMs) .. "\r\n")
		writer:write("--- Excluidos internos por regla estructural ---\r\n")
		local exclusionReasons = {}
		for reason in pairs(report.excludedInternalByReason or {}) do
			exclusionReasons[#exclusionReasons + 1] = reason
		end
		table.sort(exclusionReasons)
		for i = 1, #exclusionReasons do
			local reason = exclusionReasons[i]
			writer:write("  " .. tostring(reason) .. " = " .. fmt(report.excludedInternalByReason[reason]) .. "\r\n")
		end
		writer:write("--- Cobertura por grupo L1 ---\r\n")
		for l1, count in pairs(report.classifiedByL1 or {}) do
			writer:write("  " .. tostring(l1) .. " = " .. fmt(count) .. "\r\n")
		end
		writer:write("--- Cobertura por fuente (evidence.primary.source) ---\r\n")
		for source, count in pairs(report.coverageBySource or {}) do
			writer:write("  " .. tostring(source) .. " = " .. fmt(count) .. "\r\n")
		end
		writer:write("--- Cobertura por confianza (evidence.primary.confidence) ---\r\n")
		for confidence, count in pairs(report.coverageByConfidence or {}) do
			writer:write("  " .. tostring(confidence) .. " = " .. fmt(count) .. "\r\n")
		end
		writer:write("--- Objetos propios de GS (grupo 14) ---\r\n")
		writer:write("  esperados=" .. fmt(report.ownItems and report.ownItems.expectedExactMappings)
			.. " encontrados=" .. fmt(report.ownItems and report.ownItems.foundExactMappings) .. "\r\n")
		writer:write("  missingExactMappings (registrado pero AUSENTE del catalogo real):\r\n")
		for i = 1, #(report.ownItems and report.ownItems.missingExactMappings or {}) do
			writer:write("    " .. tostring(report.ownItems.missingExactMappings[i]) .. "\r\n")
		end
		writer:write("  ownModuleTypesUnmapped (modulo/disco real sin dar de alta en EXACT):\r\n")
		for i = 1, #(report.ownItems and report.ownItems.ownModuleTypesUnmapped or {}) do
			writer:write("    " .. tostring(report.ownItems.ownModuleTypesUnmapped[i]) .. "\r\n")
		end
		writer:write("--- Colisiones de precedencia (mas de un bloque reclamo el mismo tipo) ---\r\n")
		for i = 1, #(report.precedenceCollisions or {}) do
			writer:write("  " .. tostring(report.precedenceCollisions[i]) .. "\r\n")
		end
		writer:write("--- Probe armas de fuego sin subtipo (combat/firearm/other, valor crudo isTwoHandWeapon()) ---\r\n")
		for i = 1, #(report.samples.firearmOtherProbe or {}) do
			writer:write("  " .. tostring(report.samples.firearmOtherProbe[i]) .. "\r\n")
		end
		writer:write("--- Probe Alimentos vs. Conocimiento (PizzaRecipe/RecipeClipping...) ---\r\n")
		for i = 1, #(report.samples.foodRecipeProbe or {}) do
			writer:write("  " .. tostring(report.samples.foodRecipeProbe[i]) .. "\r\n")
		end
		writer:write("--- Probe FluidContainer (BottleOpener/JarLid/CookieJar...) ---\r\n")
		for i = 1, #(report.samples.fluidContainerProbe or {}) do
			writer:write("  " .. tostring(report.samples.fluidContainerProbe[i]) .. "\r\n")
		end
		writer:write("--- Probe tier/variant hardware propio Tablet (dev19, verificacion extremo a extremo de dev18) ---\r\n")
			for i = 1, #(report.samples.tierVariantProbe or {}) do
				writer:write("  " .. tostring(report.samples.tierVariantProbe[i]) .. "\r\n")
			end
			writer:write("--- isDebugOnly()==true confirmado (ya aplicado como blindaje en GS_NativeClassifierApi.lua -> other/debug; conteo/muestra aparte, independiente del resultado de clasificacion, para verificar sin ambiguedad si la señal aparecio de verdad) ---\r\n")
		writer:write("  total=" .. fmt(report.debugOnlyCount) .. "\r\n")
		for i = 1, #(report.samples.debugOnly or {}) do
			writer:write("  " .. tostring(report.samples.debugOnly[i]) .. "\r\n")
		end
		writer:write("--- Posibles tipos internos/de desarrollo (diagnostico por nombre, NUNCA usado para clasificar) ---\r\n")
		writer:write("  total=" .. fmt(report.likelyInternalOrDebugCount) .. "\r\n")
		for i = 1, #(report.samples.likelyInternalOrDebug or {}) do
			writer:write("  " .. tostring(report.samples.likelyInternalOrDebug[i]) .. "\r\n")
		end
		-- dev13 (pedido explicito de sistemas): "agrupar los 2540 restantes
		-- por evidencia real y decidir el siguiente bloque basandonos en
		-- cantidades, no en 20 ejemplos aleatorios" - top 30 tokens/modulos
		-- de nombre mas frecuentes SOLO entre lo sin clasificar (el
		-- inventario TSV completo, fichero aparte, tiene el detalle fila a
		-- fila; esto es el resumen rapido de un vistazo en el log principal).
		writer:write("--- Top 30 tokens de nombre mas frecuentes en lo sin clasificar ---\r\n")
		local tokenPairs = {}
		for token, count in pairs(report.tokenFrequency or {}) do
			tokenPairs[#tokenPairs + 1] = { token = token, count = count }
		end
		table.sort(tokenPairs, function(a, b) return a.count > b.count end)
		for i = 1, math.min(30, #tokenPairs) do
			writer:write("  " .. tokenPairs[i].token .. " = " .. fmt(tokenPairs[i].count) .. "\r\n")
		end
		writer:write("--- Modulos con mas tipos sin clasificar ---\r\n")
		local modulePairs = {}
		for moduleName, count in pairs(report.moduleFrequency or {}) do
			modulePairs[#modulePairs + 1] = { moduleName = moduleName, count = count }
		end
		table.sort(modulePairs, function(a, b) return a.count > b.count end)
		for i = 1, math.min(20, #modulePairs) do
			writer:write("  " .. modulePairs[i].moduleName .. " = " .. fmt(modulePairs[i].count) .. "\r\n")
		end
		-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev13):
		-- este log anunciaba "ver ...tsv" ANTES de saber si el segundo
		-- fichero se habia creado de verdad - quien llama (GS_NativeAuditServer.lua)
		-- ya escribe report.unclassifiedTsvOk/unclassifiedTsvError ANTES de
		-- invocar esta funcion, para poder informar GENERADO/NO GENERADO con
		-- la causa real.
		if report.unclassifiedTsvOk then
			writer:write("--- Inventario completo de lo sin clasificar: GENERADO (" .. tostring(report.diagnosticUnclassifiedFile or UNCLASSIFIED_TSV_NAME) .. ") ---\r\n")
		else
			writer:write("--- Inventario completo de lo sin clasificar: NO GENERADO (" .. tostring(report.unclassifiedTsvError) .. ") ---\r\n")
		end
		if report.censusTsvOk then
			writer:write("--- Censo completo de catalogo: GENERADO (" .. tostring(report.diagnosticCensusFile or CENSUS_TSV_NAME) .. ") ---\r\n")
		else
			writer:write("--- Censo completo de catalogo: NO GENERADO (" .. tostring(report.censusTsvError) .. ") ---\r\n")
		end
		writer:write("--- Muestras (maximo " .. tostring(MAX_SAMPLES_PER_BUCKET) .. " por bloque, "
			.. tostring(MAX_SAMPLES_WEAK_SOURCE) .. " para heuristicas debiles) ---\r\n")
		for _, bucketName in ipairs({ "pending", "unclassified", "invalidPath", "classifierErrors" }) do
			local list = report.samples[bucketName] or {}
			writer:write(bucketName .. " (" .. tostring(#list) .. " en muestra):\r\n")
			for i = 1, #list do
				writer:write("  " .. tostring(list[i]) .. "\r\n")
			end
		end
		writer:write("--- Muestras por fuente (samplesBySourceAndPath) ---\r\n")
		for source, list in pairs(report.samples.bySource or {}) do
			writer:write(tostring(source) .. " (" .. tostring(#list) .. " en muestra):\r\n")
			for i = 1, #list do
				writer:write("  " .. tostring(list[i]) .. "\r\n")
			end
		end
		writer:close()
	end)
	return okWrite == true
end

--- Inventario COMPLETO (una fila por fullType sin clasificar) en formato
--- TSV, separado del log principal a proposito - puede tener miles de
--- filas. Pedido explicito del equipo de sistemas (dev13): "esto no debe
--- enviarse por red ni mostrarse en la UI; solamente escribirse a fichero
--- al ejecutar la auditoria manual" - GS_Server.lua nunca lee ni reenvia
--- este fichero al cliente, solo el resumen de siempre.
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev12): el TSV
-- anunciado en el log NUNCA se creaba - `row.bodyLocation` es `nil` para
-- la mayoria de objetos sin clasificar (no equipables), y Kahlua/Lua 5.1
-- revienta `table.concat` en cuanto encuentra un `nil` dentro de la lista.
-- La excepcion quedaba absorbida por el `pcall` exterior, `writer:close()`
-- nunca se llamaba, y `GS_Server.lua` ignoraba el `false` devuelto - "el
-- log anuncia el fichero, pero no existe en ningún sitio". `tsvCell()`
-- convierte cualquier valor (incluido `nil`) a texto seguro y sustituye
-- tabuladores/CR/LF que pudieran colarse dentro de un valor real (nunca
-- deberian romper las columnas del TSV).
---@param value any
---@return string
local function tsvCell(value)
	local text = tostring(value or "")
	return (text:gsub("[\t\r\n]", " "))
end

--- Inventario COMPLETO (una fila por fullType sin clasificar) en formato
--- TSV, separado del log principal a proposito - puede tener miles de
--- filas. Pedido explicito del equipo de sistemas (dev13): "esto no debe
--- enviarse por red ni mostrarse en la UI; solamente escribirse a fichero
--- al ejecutar la auditoria manual" - GS_Server.lua nunca lee ni reenvia
--- este fichero al cliente, solo el resumen de siempre.
---@param report table
---@return boolean ok
---@return string|nil errorMessage fila/motivo si `ok` es false, para que quien llame pueda registrarlo
function GlobalStorageSiK.NativeAudit.writeUnclassifiedTsv(report)
	if not getFileWriter then return false, "getFileWriter_unavailable" end
	local inventory = report.unclassifiedInventory
	if not inventory or #inventory == 0 then return false, "empty_inventory" end
	local fileName = (report and report.diagnosticUnclassifiedFile) or UNCLASSIFIED_TSV_NAME
	local ok, writer = pcall(getFileWriter, fileName, true, false)
	if not ok or not writer then return false, "getFileWriter_failed" end
	local rowsWritten = 0
	local okWrite, errMsg = pcall(function()
		writer:write("fullType\tmodule\ttypeName\tbodyLocation\tweaponCategories\tammoType\ttokens\r\n")
		for i = 1, #inventory do
			local row = inventory[i]
			writer:write(table.concat({
				tsvCell(row.fullType), tsvCell(row.module), tsvCell(row.typeName),
				tsvCell(row.bodyLocation), tsvCell(row.weaponCategories),
				tsvCell(row.ammoType), tsvCell(row.tokens),
			}, "\t") .. "\r\n")
			rowsWritten = rowsWritten + 1
		end
	end)
	-- El writer SIEMPRE se cierra, escriba lo que escriba lo de arriba -
	-- una fila que fallara antes ni siquiera cerraba el fichero.
	pcall(function() writer:close() end)
	if not okWrite then
		return false, "row_" .. tostring(rowsWritten + 1) .. "_failed: " .. tostring(errMsg)
	end
	return true, nil
end

--- Lista completa server-side de tipos internos excluidos del contador
--- unclassified. Nunca se envia por red; el cliente recibe solo el contador y
--- la ruta relativa del fichero.
---@param report table
---@return boolean ok
---@return string|nil errorMessage
function GlobalStorageSiK.NativeAudit.writeExcludedInternalTsv(report)
	if not getFileWriter then return false, "getFileWriter_unavailable" end
	local inventory = report.excludedInternalInventory or {}
	local fileName = report and report.diagnosticExcludedInternalFile
	if not fileName then return false, "missing_file_name" end
	local ok, writer = pcall(getFileWriter, fileName, true, false)
	if not ok or not writer then return false, "getFileWriter_failed" end
	local rowsWritten = 0
	local okWrite, errMsg = pcall(function()
		writer:write("fullType\treason\tbodyLocation\r\n")
		for i = 1, #inventory do
			local row = inventory[i]
			writer:write(table.concat({
				tsvCell(row.fullType), tsvCell(row.reason), tsvCell(row.bodyLocation),
			}, "\t") .. "\r\n")
			rowsWritten = rowsWritten + 1
		end
	end)
	pcall(function() writer:close() end)
	if not okWrite then
		return false, "row_" .. tostring(rowsWritten + 1) .. "_failed: " .. tostring(errMsg)
	end
	return true, nil
end

--- Censo completo DEV32.3: una fila por ScriptItem que la auditoria recorrio,
--- incluida cualquier ruta clasificada, pendiente, excluida o invalida. Se
--- conserva solo en diagnosticos del servidor; el resumen de red no cambia.
---@param report table
---@return boolean ok
---@return string|nil errorMessage
function GlobalStorageSiK.NativeAudit.writeCensusTsv(report)
	if not getFileWriter then return false, "getFileWriter_unavailable" end
	local inventory = report and report.censusInventory
	if not inventory then return false, "missing_inventory" end
	local fileName = report.diagnosticCensusFile or CENSUS_TSV_NAME
	local ok, writer = pcall(getFileWriter, fileName, true, false)
	if not ok or not writer then return false, "getFileWriter_failed" end
	local rowsWritten = 0
	local okWrite, errMsg = pcall(function()
		writer:write("fullType\toutcome\tl1\tl2\tl3\tsource\tconfidence\treason\tbodyLocation\r\n")
		for i = 1, #inventory do
			local row = inventory[i]
			writer:write(table.concat({
				tsvCell(row.fullType), tsvCell(row.outcome), tsvCell(row.l1),
				tsvCell(row.l2), tsvCell(row.l3), tsvCell(row.source),
				tsvCell(row.confidence), tsvCell(row.reason), tsvCell(row.bodyLocation),
			}, "\t") .. "\r\n")
			rowsWritten = rowsWritten + 1
		end
	end)
	pcall(function() writer:close() end)
	if not okWrite then
		return false, "row_" .. tostring(rowsWritten + 1) .. "_failed: " .. tostring(errMsg)
	end
	return true, nil
end
