-- Language-neutral selectors from PZ 42.20 Food.getName(IsoPlayer).
-- A group records every state and whether its members share the same label.
GlobalStorageSiK.FoodPresentation = {}
local Food = GlobalStorageSiK.FoodPresentation
Food.order = {"Fresh","Stale","Rotten","Burnt","Cooked","Grilled","Toasted","Uncooked","Frozen"}
local allowed={}
for _,key in ipairs(Food.order) do allowed[key]=true end
local function tag(item,key)
	if not ItemTag or not ItemTag[key] or not item.hasTag then return nil end
	local ok,value=pcall(function()return item:hasTag(ItemTag[key])end)
	if ok and type(value)=="boolean" then return value end
end
function Food.captureNameState(item,state,boolean,scalar)
	local age,off,maximum=scalar(item,"getAge"),scalar(item,"getOffAge"),scalar(item,"getOffAgeMax")
	local fertilized=boolean(item,"isFertilized")
	if type(age)~="number" or type(off)~="number" or type(maximum)~="number"
		or age~=age or off~=off or maximum~=maximum or fertilized==nil or state.burnt==nil then return nil end
	local keys={}
	if fertilized then keys[#keys+1]="Fresh" end
	if state.burnt then keys[#keys+1]="Burnt"
	elseif not fertilized then
		if off<1000000000 and age<off then keys[#keys+1]="Fresh"
		elseif maximum<1000000000 and age>=maximum then keys[#keys+1]="Rotten"
		elseif maximum<1000000000 and age>=off then keys[#keys+1]="Stale" end
	end
	local hidden=tag(item,"HIDE_COOKED")
	if state.cooked and not state.burnt and hidden==false then
		if tag(item,"GRILLED")==true then keys[#keys+1]="Grilled"
		elseif tag(item,"TOASTABLE")==true then keys[#keys+1]="Toasted"
		else keys[#keys+1]="Cooked" end
	elseif boolean(item,"isCookable")==true and not state.burnt and hidden==false
		and tag(item,"HIDE_UNCOOKED")==false then keys[#keys+1]="Uncooked" end
	if state.frozen then keys[#keys+1]="Frozen" end
	return table.concat(keys,",")
end
function Food.keys(state)
	local keys={}
	if type(state)~="table" then return keys end
	if type(state.nameState)=="string" then
		for key in string.gmatch(state.nameState,"[^,]+") do if allowed[key] then keys[#keys+1]=key end end
		return keys
	end
	-- Legacy snapshots have no cookability/tags. Never infer raw from !cooked.
	if state.burnt then keys[#keys+1]="Burnt"
	else
		if state.rotten then keys[#keys+1]="Rotten" elseif state.fresh then keys[#keys+1]="Fresh" end
		if state.cooked then keys[#keys+1]="Cooked" end
	end
	if state.frozen then keys[#keys+1]="Frozen" end
	return keys
end
function Food.aggregate(parent,state,count)
	if not state then return end
	local keys=Food.keys(state)
	local signature=table.concat(keys,",")
	if parent.foodStateKey==nil then parent.foodStateKey=signature
	elseif parent.foodStateKey~=signature then parent.foodMixed=true end
	parent.foodSummary=parent.foodSummary or {}
	parent.foodSummaryCounts=parent.foodSummaryCounts or {}
	for _,key in ipairs(keys) do
		parent.foodSummary[key]=true
		parent.foodSummaryCounts[key]=(parent.foodSummaryCounts[key] or 0)+(count or 0)
	end
end
return Food
