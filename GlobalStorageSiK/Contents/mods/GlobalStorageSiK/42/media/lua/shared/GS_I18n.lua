--[[
	GlobalStorageSiK - Textos UI con fallback seguro (B42)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Evita excepciones Java en getText y claves crudas en UI.
]]

GlobalStorageSiK.I18n = GlobalStorageSiK.I18n or {}

GlobalStorageSiK.I18n.DEFAULTS = {
	IGUI_GS_OpenTerminal = "Open Global Storage",
	IGUI_GS_TerminalTitle = "Global Storage SiK",
	IGUI_GS_TabHome = "Home",
	IGUI_GS_TabNetwork = "Network",
	IGUI_GS_TabItems = "Items",
	IGUI_GS_TabConfig = "Setup",
	IGUI_GS_TabNodes = "Containers",
	IGUI_GS_TabCraft = "Craft",
	IGUI_GS_TabWarehouse = "Warehouse",
	IGUI_GS_TabAddons = "Addons",
	IGUI_GS_AddonsSectionTitle = "Network addons",
	IGUI_GS_AddonsIntro = "Read the addon magazine, craft the install module, then install it here. Each module is bound to this terminal.",
	IGUI_GS_AddonsNeedTerminal = "Open the terminal from a placed GS unit to manage addons.",
	IGUI_GS_AddonsEmpty = "No addons registered. Install optional addon mods from the Workshop.",
	IGUI_GS_AddonInstallBtn = "Install",
	IGUI_GS_AddonUninstallBtn = "Remove",
	IGUI_GS_AddonUnknown = "Unknown addon",
	IGUI_GS_AddonDescGeneric = "Network extension module.",
	IGUI_GS_AddonStatusMissingMod = "Workshop mod not active.",
	IGUI_GS_AddonStatusModOff = "Enable the addon mod in your mod list.",
	IGUI_GS_AddonStatusReady = "Read magazine, craft module, keep in inventory to install.",
	IGUI_GS_AddonStatusInstalled = "Installed on this terminal.",
	IGUI_GS_AddonStatusNeedMagazine = "Read the addon magazine first.",
	IGUI_GS_AddonBayTitle = "Expansion bay",
	IGUI_GS_AddonBayHint = "M = manual read · + = module installed · border shows readiness.",
	IGUI_GS_AddonMagOk = "Manual: recipes unlocked.",
	IGUI_GS_AddonMagMissing = "Manual: read the addon magazine to unlock the module recipe.",
	IGUI_GS_AddonModuleOk = "Module: ready in your inventory.",
	IGUI_GS_AddonModuleMissing = "Module: craft the install module or keep it in your inventory.",
	IGUI_GS_AddonCookTitle = "Cook",
	IGUI_GS_AddonCookDesc = "Cook add-on: installable module (Electricity 5). Craft and install from Add-ons tab.",
	IGUI_GS_PermCharacterHintDropdown = "Add access only from the dropdowns below.",
	IGUI_GS_PermOnlinePickLabel = "Connected players",
	IGUI_GS_PermFactionPickLabel = "Faction access",
	IGUI_GS_PermPickWholeFaction = "Whole faction: {1}",
	IGUI_GS_PermPickFactionMember = "Member: {1}",
	IGUI_GS_PickFactionAccess = "Select faction option…",
	IGUI_GS_PickMember = "Select player or faction...",
	IGUI_GS_PickGroupFaction = "My Faction",
	IGUI_GS_PickGroupServer = "Server",
	IGUI_GS_PickGroupServerEmpty = "Server (nobody online)",
	IGUI_GS_LeftNetworkMsg = "You left the network",
	IGUI_GS_TerminalDefaultNameFmt = "Terminal {1}",
	IGUI_GS_MemberEditorLeaveBtn = "Leave network",
	IGUI_GS_MemberEditorLeaveConfirm = "Leave this network? If you're the owner, ownership passes automatically to another admin or member, same as on death.",
	IGUI_GS_MemberZoneAccessTitle = "Container access by zone",
	IGUI_GS_MemberZoneAccessHint = "Checked zones allow access to all their containers. New zones are allowed by default.",
	IGUI_GS_MemberZoneSelectAll = "Select all",
	IGUI_GS_MemberZoneDeselectAll = "Deselect all",
	IGUI_GS_MemberZoneSave = "Save zone access",
	IGUI_GS_MemberZoneAccessUpdated = "Zone access updated",
	IGUI_GS_MemberZoneAccessFailed = "Could not update zone access",
	IGUI_GS_PermAddBlockTitle = "Grant access",
	IGUI_GS_AddMember = "Add",
	IGUI_GS_BlockedTabletAddon = "Craft and install the Wireless Tablet Link module on a GS terminal, and enable the tablet addon mod.",
	IGUI_GS_SectionCraftModRecipes = "Mod recipes",
	IGUI_GS_CraftModRecipesHint = "Terminal and wireless tablet. Materials are taken from your inventory.",
	IGUI_GS_CraftSessionAccessLost = "Session closed: terminal access lost.",
	IGUI_GS_CraftSessionActive = "Session active: {1} network containers available for crafting.",
	IGUI_GS_CraftSessionInactive = "No network-inventory craft session active.",
	IGUI_GS_CraftNoModRecipes = "No mod recipes available.",
	IGUI_GS_SectionStatus = "Network status",
	IGUI_GS_SectionScan = "Scan",
	IGUI_GS_SectionItems = "Network inventory",
	IGUI_GS_SectionZones = "Zones",
	IGUI_GS_StatsZones = "Zones: {1}",
	IGUI_GS_StatsNodes = "Containers: {1}",
	IGUI_GS_StatsItems = "Item types: {1}",
	IGUI_GS_StatsFuel = "Consumption: {1} /h",
	IGUI_GS_StatsFuelTooltipOn = "Base consumption: {1}\nPer-container consumption: {2} x {3} containers\nTotal consumption: {4} (generator fuel unit) per game hour.\nOnly applies while the network is running off a nearby active generator, never off the normal grid.",
	IGUI_GS_StatsFuelTooltipOff = "Fuel consumption is turned off (sandbox option 'Consume generator fuel'). The network doesn't consume anything, it just requires power to be present.",
	IGUI_GS_NetAccessPhysical = "Access: placed terminal",
	IGUI_GS_NetAccessWireless = "Access: wireless tablet",
	IGUI_GS_NetAccessBypass = "Access: unrestricted (sandbox)",
	IGUI_GS_NetRangePhysical = "Terminal range: {1} tiles",
	IGUI_GS_NetRangeWireless = "Tablet range: {1} tiles",
	IGUI_GS_WeightUsage = "Weight: {1} / {2} kg ({3})",
	IGUI_GS_WeightUsedOnly = "Weight used: {1} kg (capacity unknown — rescan)",
	IGUI_GS_WeightWarn = "Storage almost full ({1})! Add crates, rescan zones, or create a new zone.",
	IGUI_GS_WeightCritical = "Storage critical ({1})! Expand soon: place more boxes and rescan.",
	IGUI_GS_WeightFull = "Network storage full. Add capacity before depositing more items.",
	IGUI_GS_SectionNodes = "Network containers",
	IGUI_GS_ZoneListSection = "Registered zones",
	IGUI_GS_ZonesManageHint = "Edit name and press Save. Rescan updates containers in that zone only. Delete removes the zone.",
	IGUI_GS_ZoneRenameLabel = "Name:",
	IGUI_GS_Rename = "Rename",
	IGUI_GS_DeleteZone = "Delete",
	IGUI_GS_SearchPlaceholder = "Search item...",
	IGUI_GS_NoItems = "No items in network. Create a zone and rescan.",
	IGUI_GS_NoNodesYet = "No containers detected in zones.",
	IGUI_GS_ShowTerminalCoverage = "Show coverage",
	IGUI_GS_HideTerminalCoverage = "Hide coverage",
	IGUI_GS_NodesPriorityHelp = "How items pick a container: 1) exact custom filter or leaf category match, 2) subcategory match (e.g. Food > Perishable), 3) main category match (e.g. Food) with no better option, 4) unrestricted container. If no container matches, the item stays in your inventory instead of taking a wrong spot.",
	IGUI_GS_NetworkId = "Network: {1}",
	IGUI_GS_Guide1 = "1. Setup: create a zone (room or MP safehouse) and rescan.",
	IGUI_GS_Guide2 = "2. Containers: rename each box and pick one category for auto-sort.",
	IGUI_GS_Guide3 = "3. Items: search, withdraw, or drag inventory -> terminal / right-click -> Transfer.",
	IGUI_GS_Guide4 = "4. Network: power status and scan summary.",
	IGUI_GS_Guide5 = "Access: hover Inventory on the left bar -> GS icon -> click.",
	IGUI_GS_Welcome = "Hover Inventory on the left bar and click the GS icon. Configure zones here, then manage containers and items.",
	IGUI_GS_CreateRoomZone = "+ Zone: current room",
	IGUI_GS_CreateBuildingZone = "+ Zone: whole building",
	IGUI_GS_CreateSafehouseZone = "+ Zone: safehouse (MP)",
	IGUI_GS_CreateSelectionZone = "+ Zone: draw with mouse",
	IGUI_GS_ZonePickStart = "Click first corner of the storage area. Right-click or ESC to cancel.",
	IGUI_GS_ZonePickFirstStored = "First corner saved at {1},{2} (floor {3}).",
	IGUI_GS_ZonePickSecond = "Click the opposite corner to finish the zone.",
	IGUI_GS_ZonePickDone = "Zone created. Rescanning network...",
	IGUI_GS_ZonePickCancelled = "Zone selection cancelled.",
	IGUI_GS_ZonePickNoSquare = "No valid tile under cursor.",
	IGUI_GS_ZonePickSameFloor = "Both corners must be on the same floor.",
	IGUI_GS_ZonePickFailed = "Could not send zone to server.",
	IGUI_GS_BlockedCraftHint = "Craft the GS terminal from the vanilla crafting menu when you have the requirements.",
	IGUI_GS_NodeRenameLabel = "Display name:",
	IGUI_GS_NodeSaveAll = "Save name and category",
	IGUI_GS_NodeBtnEnable = "Enable in network",
	IGUI_GS_NodeBtnDisable = "Disable in network",
	IGUI_GS_NodeBtnInclude = "Include in network",
	IGUI_GS_NodeBtnExclude = "Exclude from network",
	IGUI_GS_NodeExpand = "Show container contents",
	IGUI_GS_NodeCollapse = "Hide container contents",
	IGUI_GS_RefreshScan = "Rescan containers",
	IGUI_GS_ZoneListTitle = "Configured zones (rename or delete):",
	IGUI_GS_NoZonesYet = "No zones yet. Create one with the buttons above.",
	IGUI_GS_ScanSummary = "Last scan: +{1} new, {2} offline",
	IGUI_GS_ScanNew = "New containers: {1}",
	IGUI_GS_ScanUpdated = "Updated: {1}",
	IGUI_GS_ScanOffline = "Offline: {1}",
	IGUI_GS_ItemTypes = "Item types in network: {1}",
	IGUI_GS_NoZones = "No containers. Create a zone in Setup and press Rescan.",
	IGUI_GS_NodesHelp = "Rename containers and pick one category. «Any» = accept all items.",
	IGUI_GS_NodesHelpShort = "Detected containers. Click a zone header to highlight all; click a row to edit and highlight one.",
	IGUI_GS_CategoryLabel = "Category:",
	IGUI_GS_CategoryAny = "Any (all items)",
	-- Improved node editor
	IGUI_GS_NodeCategoriesLabel   = "Accepted categories:",
	IGUI_GS_NodeNoCats            = "No category (accepts any item)",
	IGUI_GS_NodeAddCatBtn         = "Add",
	IGUI_GS_NodeRemoveCatBtn      = "X",
	IGUI_GS_NodePriorityLabel     = "Fill priority:",
	IGUI_GS_NodePriorityHigh      = "High - fill first",
	IGUI_GS_NodePriorityNormal    = "Normal",
	IGUI_GS_NodePriorityLow       = "Low - fill last",
	IGUI_GS_NodePriorityHint      = "1 = highest priority, 100 = lowest",
	IGUI_GS_NodePriorityPresetHigh   = "High (10)",
	IGUI_GS_NodePriorityPresetNormal = "Normal (50)",
	IGUI_GS_NodePriorityPresetLow    = "Low (90)",
	IGUI_GS_NodeNotesLabel        = "Location / notes:",
	IGUI_GS_NodeNotesHint         = "E.g.: Left hallway, next to the entrance...",
	IGUI_GS_NodeAddCatComboHint   = "Select category...",
	IGUI_GS_Apply                 = "Apply",
	IGUI_GS_NodeCategoryMainLabel = "Category:",
	IGUI_GS_NodeCategorySubLabel  = "Subcategory:",
	-- Preconfigured subcategories (nested under their vanilla parent category in the combo)
	IGUI_GS_SubCat_FoodCold       = "Refrigerated / Freezable",
	IGUI_GS_SubCat_FoodDry        = "Dry / Non-perishable",
	IGUI_GS_SubCat_FoodSeed       = "Seeds",
	IGUI_GS_SubCat_ToolFarm       = "Farming tools",
	IGUI_GS_SubCat_MedAid         = "First aid",
	IGUI_GS_SubCat_MedSurgery     = "Surgery",
	IGUI_GS_SubCat_WeaponFirearm  = "Firearms",
	IGUI_GS_SubCat_WeaponMelee    = "Melee weapons",
	-- Tools
	IGUI_GS_SubCat_ToolWeapon     = "Combat tools",
	-- Literature
	IGUI_GS_SubCat_LitRecipe      = "Recipe magazines and manuals",
	IGUI_GS_SubCat_LitSkillBook   = "Skill books",
	IGUI_GS_SubCat_LitReading     = "Reading and entertainment",
	-- Materials by trade
	IGUI_GS_SubCat_MatMetal       = "Metal and forging",
	IGUI_GS_SubCat_MatLeather     = "Leather and hides",
	IGUI_GS_SubCat_MatWood        = "Wood and construction",
	IGUI_GS_NodeOffline = " [offline]",
	IGUI_GS_CategoriesHint = "Categories (comma separated):",
	IGUI_GS_Save = "Save",
	IGUI_GS_NodeEnabled = "Active",
	IGUI_GS_NodeDisabled = "Inactive",
	IGUI_GS_Search = "Search",
	IGUI_GS_FilterCategoryLabel = "Category:",
	IGUI_GS_FilterCategoryAll = "All categories",
	IGUI_GS_FilterSubCategoryAll = "All subcategories",
	IGUI_GS_BulkDeposit = "Store all",
	IGUI_GS_Withdraw = "Withdraw",
	IGUI_GS_WithdrawAll = "Withdraw all of this type",
	IGUI_GS_WithdrawOne = "Withdraw 1 unit",
	IGUI_GS_WithdrawType = "Withdraw all of this type ({1})",
	IGUI_GS_WithdrawAmount = "Withdraw amount",
	IGUI_GS_WithdrawAmountCustom = "Enter amount...",
	IGUI_GS_WithdrawAmountMax = "All available ({1})",
	IGUI_GS_WithdrawAmountPrompt = "How many units to withdraw?",
	IGUI_GS_WithdrawSelectionOne = "Withdraw 1 of each selected",
	IGUI_GS_WithdrawSelectionAll = "Withdraw all of each selected",
	IGUI_GS_QuantityPrompt = "Quantity",
	IGUI_GS_InvalidQuantity = "Invalid quantity",
	IGUI_GS_WithdrawDest = "Withdraw to",
	IGUI_GS_WithdrawDestAuto = "Active panel / under mouse",
	IGUI_GS_TransferAmount = "Transfer amount",
	IGUI_GS_TransferAmountCustom = "Enter amount...",
	IGUI_GS_TransferAmountMax = "Entire stack ({1})",
	IGUI_GS_TransferAmountPrompt = "How many units to transfer?",
	IGUI_GS_Examine = "Examine",
	IGUI_GS_ViewDetails = "View item details",
	IGUI_GS_DetailType = "Type: {1}",
	IGUI_GS_DetailCategory = "Category: {1}",
	IGUI_GS_DetailWeight = "Unit weight: {1} kg",
	IGUI_GS_DetailCount = "Quantity in this network: {1}",
	IGUI_GS_NetworkCountLine = "{1}: {2} in your network",
	IGUI_GS_NetworkCountNone = "Not in any of your networks",
	IGUI_GS_NoNetworksYet = "You don't have any storage network yet",
	IGUI_GS_ContextWithdraw = "Withdraw from network",
	IGUI_GS_ColName = "Name",
	IGUI_GS_ColCategory = "Category",
	IGUI_GS_CategoryTooltipTitle = "Full category",
	IGUI_GS_CategoryTooltipMain = "Category: {1}",
	IGUI_GS_CategoryTooltipSub = "Subcategory: {1}",
	IGUI_GS_CategoryTooltipLeaf = "Detail: {1}",
	IGUI_GS_NodeMoreCategories = "+ {1} more accepted categories",
	IGUI_GS_ColCount = "Qty",
	IGUI_GS_ColZone = "Zone",
	IGUI_GS_ColStatus = "Status",
	IGUI_GS_ColTypes = "Types",
	IGUI_GS_ColNodePriority = "Priority",
	IGUI_GS_NodesTableHint = "Click a container to open the editor.",
	IGUI_GS_NodeEditorTitle = "Edit container",
	IGUI_GS_NodeContentsTitle = "Container contents",
	IGUI_GS_DepositAllCombined = "Store all (player + nearby)",
	IGUI_GS_DepositAll = "Store all (inventory + bags)",
	IGUI_GS_DepositMain = "Main inventory only",
	IGUI_GS_DepositBag = "Bag {1}",
	IGUI_GS_DepositAllNearby = "All nearby containers (trunks, crates...)",
	IGUI_GS_DepositVehiclePart = "{1} (vehicle)",
	IGUI_GS_DepositNamed = "{1} (nearby)",
	IGUI_GS_DepositContainer = "Nearby container",
	IGUI_GS_GenericContainerName = "Container",
	IGUI_GS_DepositFailRemoteDisabled = "Remote transfer disabled",
	IGUI_GS_DepositFailNoPower = "The network has no power",
	IGUI_GS_DepositFailNoAccess = "No access to the container",
	IGUI_GS_DepositFailInvalid = "Invalid item or container",
	IGUI_GS_DepositFailNetworkSource = "The item is already in the network",
	IGUI_GS_DepositFailNoSpace = "Storage full. Add more crates, rescan the zone, or create a new zone.",
	IGUI_GS_DepositFailNoMatch = "No matching container found (kept in your inventory). Configure a category for this item or disable «Reject deposit if no matching container» in sandbox options.",
	IGUI_GS_DepositFailGeneric = "Couldn't transfer the item. Check it's still in your inventory and try again.",
	IGUI_GS_DepositSummary = "Deposited: {1} | Skipped: {2} | Failed: {3}",
	IGUI_GS_DepositCorpse = "Corpse (nearby)",
	IGUI_GS_ContextTransfer = "Transfer to Global Storage",
	IGUI_GS_TransferThis = "This item",
	IGUI_GS_TransferSelection = "Current selection",
	IGUI_GS_TransferContainer = "Entire container",
	IGUI_GS_DropHint = "Drag items here or right-click inventory -> Transfer to Global Storage",
	IGUI_GS_DepositPending = "Sending to network...",
	IGUI_GS_WithdrawPending = "Withdrawing from network...",
	IGUI_GS_WithdrawDragHint = "Drag a row to an inventory panel to withdraw there",
	IGUI_GS_WithdrawPending = "Withdrawing from network...",
	IGUI_GS_WithdrawDragHint = "Drag a row to an inventory panel to withdraw there",
	IGUI_GS_BulkResult = "Stored: {1} | Skipped: {2}",
	IGUI_GS_WithdrawOk = "Item withdrawn to your inventory",
	IGUI_GS_WithdrawFail = "Could not withdraw: {1}",
	IGUI_GS_WithdrawnCount = "Withdrawn: {1}",
	IGUI_GS_WithdrawnPartial = "Withdrawn: {1} of {2} requested",
	IGUI_GS_WithdrawErrorReason = "Error: {1}",
	IGUI_GS_ZoneLimitReached = "Zone limit reached",
	IGUI_GS_InvalidEntry = "Invalid entry",
	IGUI_GS_AlreadyMarked = "Already marked",
	IGUI_GS_ContainerLimitReached = "Container limit reached",
	IGUI_GS_AccessInvalidPlayer = "Invalid player",
	IGUI_GS_InvalidZone = "Invalid zone",
	IGUI_GS_NoRoom = "No room",
	IGUI_GS_NoBuildingOrSafehouse = "No building or safehouse at this position",
	IGUI_GS_NoBuilding = "No building at this position",
	IGUI_GS_InvalidArea = "Invalid area",
	IGUI_GS_AreaSizeInvalid = "Area too small or too large",
	IGUI_GS_RecipeAnalysisDone = "Recipe analysis complete",
	IGUI_GS_EmptyUsername = "Empty username",
	IGUI_GS_CategoryAdded = "Category added",
	IGUI_GS_CategoryDuplicate = "Duplicate category",
	IGUI_GS_UserAdded = "User added",
	IGUI_GS_UserAlreadyExists = "User already exists",
	IGUI_GS_PowerOk = "Power: OK",
	IGUI_GS_PowerOff = "Power: NO SUPPLY",
	IGUI_GS_UseTerminalTablet = "Open network terminal",
	IGUI_GSSiK_UseAccessTablet = "Open remote terminal (access)",
	IGUI_GSSiK_UseCraftTablet = "Open remote terminal (access + Craft tab)",
	IGUI_GSSiK_UseBuilderTablet = "Open remote terminal (access + Build tab)",
	IGUI_GSSiK_UseMasterTablet = "Open remote terminal (access + Craft + Build)",
	IGUI_GSSiK_AccessTabletName = "GS Tablet",
	IGUI_GSSiK_CraftTabletName = "GS Craft Tablet",
	IGUI_GSSiK_BuilderTabletName = "GS Builder Tablet",
	IGUI_GSSiK_MasterTabletName = "GS Master Tablet",
	IGUI_GS_ContextMenu = "Global Storage",
	IGUI_GS_MarkContainer = "Add container to network",
	IGUI_GS_UnmarkContainer = "Remove container from network",
	IGUI_GS_QueryIndex = "Query network inventory",
	IGUI_GS_NoCategories = "No categories assigned",
	IGUI_GS_AddCategory = "Add",
	IGUI_GS_AssignCategory = "Assign",
	IGUI_GS_TabPermissions = "Permissions",
	IGUI_GS_PermOwner = "Owner: {1}",
	IGUI_GS_FactionOnly = "Faction members only",
	IGUI_GS_FactionOnlyOn = "Faction only: ON",
	IGUI_GS_AddUser = "Add",
	IGUI_GS_Remove = "Remove",
	IGUI_GS_NoPermUsers = "No extra characters. Owner always has access.",
	IGUI_GS_PermUsersTitle = "Authorized characters",
	IGUI_GS_BlockedTitle = "No terminal nearby",
	IGUI_GS_BlockedMessage = "You need a terminal. Find the magazine, read it, and craft the one below.",
	IGUI_GS_BlockedApproachHint = "Already placed a terminal? Walk up to it (about {1} tiles) to open the network.",
	IGUI_GS_BlockedApproachTablet = "You have the tablet: stay within wireless range of a placed terminal.",
	IGUI_GS_BlockedApproachCraft = "No terminal in range yet. Craft one below or move closer to your placed unit.",
	IGUI_GS_BlockedSkillIntro = "Skill: Electricity — level {2} required (you have {1}).",
	IGUI_GS_BlockedRangeIntro = "Placed terminal: access within {1} tiles.",
	IGUI_GS_BlockedRangeHint = "Physical range: {1} tiles | Wireless tablet range: {2} tiles",
	IGUI_GS_BlockedRangePhysical = "Physical range: {1} tiles",
	IGUI_GS_BlockedRangeWireless = "Wireless tablet range: {1} tiles",
	IGUI_GS_BlockedCraftSection = "Craft access devices",
	IGUI_GS_CraftNow = "Craft",
	IGUI_GS_BuildNow = "Build",
	IGUI_GS_BuildMissing = "Missing requirements",
	IGUI_GS_BuildReady = "Ready to place: {1}",
	IGUI_GS_BuildPlaced = "Terminal placed in the world",
	IGUI_GS_BuildCancelled = "Build cancelled (materials refunded)",
	IGUI_GS_BuildPlaceHint = "Click to place the terminal. ESC cancels.",
	IGUI_GS_BuildPlaceConfirm = "Click here to confirm placement",
	IGUI_GS_BuildInvalidSquare = "Cannot place on this tile",
	IGUI_GS_BuildNoPending = "No pending build",
	IGUI_GS_BuildAlreadyPending = "You already have a terminal waiting to be placed",
	IGUI_GS_BuildUseConstruct = "Use Build in the GS window (not craft)",
	IGUI_GS_CraftMissing = "Missing materials",
	IGUI_GS_CraftOk = "Crafted: {1}",
	IGUI_GS_CraftFail = "Could not craft",
	IGUI_GS_CraftCancelled = "Installation cancelled (interrupted). Try again.",
	IGUI_GS_CraftMaterialsFail = "Not enough materials in inventory",
	IGUI_GS_CraftSkillFail = "Requires Electricity level {1}",
	IGUI_GS_CraftSkillReq = "Skill: Electricity {1}",
	IGUI_GS_InstallTerminalName = "GS Terminal",
	IGUI_GS_InstallTerminalTitle = "Install GS Terminal",
	IGUI_GS_InstallTerminalIntro = "Convert this vanilla desktop into a GS network terminal. You need the GS magazine, the GS Network OS Disk (found in the world, not consumed), and Electricity skill. After installation you can place it on the map.",
	IGUI_GS_IngFloppyDisk = "GS Network OS Disk (kept)",
	IGUI_GS_CraftFloppyFail = "You need the GS Network OS Disk in your inventory",
	IGUI_GS_InstallTerminalBtn = "Install",
	IGUI_GS_InstallTerminalMenu = "Install GS Terminal",
	IGUI_GS_InstallTerminalWorking = "Installing terminal…",
	IGUI_GS_IngVanillaDesktop = "Vanilla desktop computer",
	IGUI_GS_CraftDesktopFail = "You need a vanilla desktop computer in your inventory",
	IGUI_GS_TerminalUnitName = "GS Terminal",
	IGUI_GS_TerminalTabletName = "GS Tablet",
	IGUI_GS_ReqBookOk = "Magazine read: {1}",
	IGUI_GS_ReqBookMissing = "Read magazine: {1}",
	IGUI_GS_ReqWorkbenchOk = "Workbench / surface: OK",
	IGUI_GS_ReqWorkbenchMissing = "Requires workbench or craft surface nearby",
	IGUI_GS_ReqLightOk = "Light: OK",
	IGUI_GS_ReqLightMissing = "Requires more light to craft here",
	IGUI_GS_CraftLightFail = "You need more light to craft here",
	IGUI_GS_CraftSkillReqLine = "Electricity: {1} / {2} required",
	IGUI_GS_CraftBookFail = "Read the GS recipe magazine for this device first",
	IGUI_GS_CraftWorkbenchFail = "You need a workbench or craft surface nearby",
	IGUI_GS_PlaceTerminal = "Place GS Terminal",
	IGUI_GS_PlaceTerminalHint = "Pick a network in the dialog and place the terminal with the furniture cursor",
	IGUI_GS_PlaceCursorCancelHint = "Right-click or ESC to cancel placement",
	IGUI_GS_NodeMembershipExcluded = "Excluded from network",
	IGUI_GS_NodeMembershipActive = "In network",
	IGUI_GS_NodeMembershipAuto = "Auto-detected",
	IGUI_GS_NodeStatusOk = "OK",
	IGUI_GS_NodeStatusError = "ERROR",
	IGUI_GS_NodeExclude = "Exclude",
	IGUI_GS_NodeInclude = "Include",
	IGUI_GS_NodeContentsLive = "Live inventory",
	IGUI_GS_NodeContentsSnapshot = "Last scan",
	IGUI_GS_NodeContentsEmpty = "Empty container",
	IGUI_GS_NodeSuggestCategory = "Suggested: {1}",
	IGUI_GS_NodeApplySuggest = "Apply",
	IGUI_GS_TransferOwnership = "Transfer ownership",
	IGUI_GS_TransferOwnershipHint = "New owner username (MP account name):",
	IGUI_GS_TransferOwnershipKeep = "Keep former owner as authorized user",
	IGUI_GS_PermCharacterHint = "Access is by character name (forename + surname), not Steam account.",
	IGUI_GS_PermOwnerCharacter = "Owner character: {1}",
	IGUI_GS_PickOnlineCharacter = "— Online character —",
	IGUI_GS_PermYourFaction = "Your faction: {1}",
	IGUI_GS_PermNoFaction = "You are not in a faction.",
	IGUI_GS_PermAddMyFaction = "Allow whole faction",
	IGUI_GS_PermAddFactionMembers = "Add faction members",
	IGUI_GS_TransferOwnershipCharacterHint = "New owner character name (forename + surname):",
	IGUI_GS_TransferOwnershipBtn = "Transfer",
	IGUI_GS_NetworkNameSection = "Network name",
	IGUI_GS_NetworkIdInternal = "ID: {1} (permanent, not editable)",
	IGUI_GS_NetworkNameHint = "Each placed terminal creates a network. The visible name can change; the ID cannot.",
	IGUI_GS_NetworkSingleHint = "Each terminal creates a unique network. A player or faction may operate several networks.",
	IGUI_GS_NetworkDefaultName = "Global storage",
	IGUI_GS_NetworkFooter = "Network: {1}",
	IGUI_GS_NetworkDisplay = "{1} (id: {2})",
	IGUI_GS_RescanAll = "Rescan all zones",
	IGUI_GS_RescanAllHint = "Detects new containers in every zone. Use per-zone Rescan for a single area.",
	IGUI_GS_Redistribute = "Auto-sort",
	IGUI_GS_RedistributeHint = "CAUTION! Experimental tool for large networks. It moves misplaced items to the highest-priority matching container. Scanning and moves now run in small background steps and may take several minutes; use it when server load is low.",
	IGUI_GS_RedistributeIdle = "Ready to auto-sort",
	IGUI_GS_RedistributeProgressIndex = "Auto-sort: preparing snapshot {1}/{2} items ({3} moved)",
	IGUI_GS_RedistributeProgressMove = "Auto-sort: checking {1}/{2} items ({3} moved)",
	IGUI_GS_RedistributeConfigLocked = "Auto-sort is running. Node, zone, filter and priority changes are temporarily disabled.",
	IGUI_GS_RedistributeRunning = "Sorting...",
	IGUI_GS_RedistributeDone = "Done!",
	IGUI_GS_ZonesCreateHint = "Stand inside the area you want to register, then pick a zone type:",
	IGUI_GS_ZoneSourceRoom = "Room",
	IGUI_GS_ZoneSourceBuilding = "Building",
	IGUI_GS_ZoneSourceSafehouse = "Safehouse",
	IGUI_GS_ZoneSourceSelection = "Selection",
	IGUI_GS_ZoneSourceManual = "Manual",
	IGUI_GS_ZoneRescan = "Rescan",
	IGUI_GS_ZoneNeverLoaded = "?",
	IGUI_GS_ZoneNodeCount = "Containers in zone: {1}",
	IGUI_GS_ZoneGroupHeader = "{1} — {2} containers",
	IGUI_GS_NodeHighlightZone = "Highlighted {1} containers in {2}",
	IGUI_GS_NodeHighlightZonePartial = "Highlighted {1} of {2} containers in {3}",
	IGUI_GS_NodeHighlightOne = "Highlighted: {1}",
	IGUI_GS_NodeHighlightNone = "Container not found in the world (offline or unloaded chunk)",
	IGUI_GS_ZoneUnknown = "Unassigned zone",
	IGUI_GS_PermSectionTitle = "Permissions",
	IGUI_GS_PermFactionsTitle = "Authorized factions",
	IGUI_GS_AddFaction = "Add",
	IGUI_GS_NoPermFactions = "No extra factions. Enable faction-only or add one by name.",
	IGUI_GS_PickOnlinePlayer = "— Pick online player —",
	IGUI_GS_AddUserManualHint = "Or type username manually:",
	IGUI_GS_PermMembersTableTitle = "Network members",
	IGUI_GS_PermColRole = "Role",
	IGUI_GS_PermColMemberName = "Name",
	IGUI_GS_PermColActions = "Actions",
	IGUI_GS_PermRoleOwner = "Owner",
	IGUI_GS_PermRoleAdmin = "Admin",
	IGUI_GS_PermRoleMember = "Member",
	IGUI_GS_PermRoleFaction = "Faction",
	IGUI_GS_PermCtxTransferOwnership = "Transfer ownership to {1}",
	IGUI_GS_PermCtxTransferOwnershipRevoke = "Transfer to {1} (revoke former owner)",
	IGUI_GS_PermCtxMakeAdmin = "Promote to Admin: {1}",
	IGUI_GS_PermCtxMakeMember = "Demote to Member: {1}",
	IGUI_GS_TerminalPresentPhys = "Present",
	IGUI_GS_TerminalMissingPhys = "Missing (removed)",
	IGUI_GS_TerminalUnverified = "Unverified (chunk unloaded)",
	IGUI_GS_TerminalSuspended = "In inventory / suspended",
	IGUI_GS_NetBlockNetworks = "GS Networks",
	IGUI_GS_NetUseSelected = "Use network",
	IGUI_GS_NetCreateNew = "New network",
	IGUI_GS_NetLinkTerminal = "Link terminal here",
	IGUI_GS_NetRefreshList = "Refresh list",
	IGUI_GS_NetNoNetworks = "No networks yet",
	IGUI_GS_NetNoActive = "none",
	IGUI_GS_NetActiveSession = "Active session",
	IGUI_GS_BlockedTerminalUnlinked = "This terminal is not linked to a network. Use Install GS Terminal or the Network tab to create or link one.",
	IGUI_GS_NetworkCreated = "New network created: {1}",
	IGUI_GS_AccessTerminalUnlinked = "Terminal not linked to a network",
	IGUI_GS_AccessTabletOutOfRange = "Tablet out of range",
	IGUI_GS_AccessTabletAddonRequired = "Install the tablet addon on the terminal",
	IGUI_GS_ZoneCreatedMsg = "Zone created: {1}",
	IGUI_GS_ContainerMarkedMsg = "Container marked",
	IGUI_GS_ContainerUnmarkedMsg = "Container unmarked",
	IGUI_GS_ContainerNotInNetworkMsg = "Not in the network",
	IGUI_GS_ZoneRescannedMsg = "Zone rescanned: +{1} new, {2} offline, {3} out of range",
	IGUI_GS_RedistributeNothingToSort = "Everything is already in the right container",
	IGUI_GS_RedistributeCompleteMsg = "Sort complete: {1} moved, {2} failed",
	IGUI_GS_FactionMembersAddedNone = "No members added (nobody online?)",
	IGUI_GS_FactionMembersAddedMsg = "{1} members added",
	IGUI_GS_ClientTerminalUpdateError = "Global Storage: error updating terminal",
	IGUI_GS_ClientTerminalOpenError = "Global Storage: error opening terminal",
	IGUI_GS_NetworkNameLengthMsg = "Name must be between 2 and 32 characters",
	IGUI_GS_NetworkNameInvalidCharsMsg = "Invalid characters in the name",
	IGUI_GS_NetworkNotFoundMsg = "Network not found",
	IGUI_GS_PermCharacterNameEmptyMsg = "Character name is empty",
	IGUI_GS_PermSelectionStale = "That player selection is no longer valid. Refresh the roster and choose the player again.",
	IGUI_GS_PermAlreadyOwnerMsg = "You are already the owner",
	IGUI_GS_PermOnlyOwnerTransferMsg = "Only the owner can transfer the network",
	IGUI_GS_PermOwnershipTransferredMsg = "Ownership transferred to {1}",
	IGUI_GS_ZoneSourceStructure = "Structure",
}

--- Sustitución literal (sin patrones Lua) para evitar corrupción de %1, %2...
---@param str string
---@param find string
---@param repl string
---@return string
function GlobalStorageSiK.I18n.plainReplace(str, find, repl)
	local idx = str:find(find, 1, true)
	if not idx then
		return str
	end
	return str:sub(1, idx - 1) .. repl .. str:sub(idx + #find)
end

--- Normaliza %s / %d / %1$s a %1, %2... (evita artefactos $s en UI).
---@param text string
---@return string
function GlobalStorageSiK.I18n.normalizeTemplate(text)
	text = tostring(text or "")
	text = text:gsub("{(%d+)}", "%%%1")
	text = text:gsub("%%(%d+)%$[sd]", "%%%1")
	local index = 0
	return text:gsub("%%[sd]", function()
		index = index + 1
		return "%" .. tostring(index)
	end)
end

--- Sustituye %1, %2... sin pasar por Java String.format.
---@param text string
---@param ... any
---@return string
function GlobalStorageSiK.I18n.formatTemplate(text, ...)
	local args = { ... }
	text = GlobalStorageSiK.I18n.normalizeTemplate(text)
	for index, value in ipairs(args) do
		text = GlobalStorageSiK.I18n.plainReplace(text, "%" .. tostring(index), tostring(value))
	end
	local fallback = 0
	text = text:gsub("%%[sd]", function()
		fallback = fallback + 1
		return tostring(args[fallback] or "")
	end)
	return text
end

--- Devuelve plantilla traducida sin argumentos de formato (seguro en B42).
---@param key string
---@return string
function GlobalStorageSiK.I18n.getTemplate(key)
	if type(getText) == "function" then
		local ok, value = pcall(getText, key)
		if ok and value and value ~= key then
			return GlobalStorageSiK.I18n.normalizeTemplate(value)
		end
	end
	return GlobalStorageSiK.I18n.normalizeTemplate(GlobalStorageSiK.I18n.DEFAULTS[key] or key)
end

--- Devuelve texto traducido; con args usa sustitución Lua (%1), no getText(args).
---@param key string
---@param ... any
---@return string
function GlobalStorageSiK.I18n.text(key, ...)
	local argCount = select("#", ...)
	local template = GlobalStorageSiK.I18n.getTemplate(key)
	if argCount <= 0 then
		return template
	end
	return GlobalStorageSiK.I18n.formatTemplate(template, ...)
end

--- Empaqueta una clave (+ args) para resolver en el idioma de quien LEE el
--- valor, no de quien lo genera. Usar solo para mensajes que el servidor
--- envía a un cliente via gsSendServerCommand (p.ej. actionResult.message):
--- getText()/I18n.text() siempre resuelve con el idioma del PROCESO que
--- llama, así que un string ya resuelto en el servidor sale en el idioma
--- del propio servidor para TODOS los clientes, sea cual sea el suyo.
--- GS_Client.lua debe resolver esto con GlobalStorageSiK.I18n.resolveRemote
--- al recibirlo, nunca reenviar el resultado de esta función tal cual.
---@param key string
---@return table
function GlobalStorageSiK.I18n.remote(key, ...)
	return { __gsI18nKey = key, __gsI18nArgs = { ... } }
end

--- Resuelve (en el idioma de ESTE proceso) un valor que puede venir ya como
--- string plano (call sites aún no migrados) o como tabla generada por
--- GlobalStorageSiK.I18n.remote(). Seguro de llamar con nil.
---@param value table|string|nil
---@return string|nil
function GlobalStorageSiK.I18n.resolveRemote(value)
	if type(value) == "table" and value.__gsI18nKey then
		return GlobalStorageSiK.I18n.text(value.__gsI18nKey, unpack(value.__gsI18nArgs or {}))
	end
	return value
end

--- Humaniza un identificador interno (sprite / tipo sin traducción).
---@param token string|nil
---@return string
function GlobalStorageSiK.I18n.humanizeToken(token)
	if not token or token == "" then
		return "?"
	end
	local text = tostring(token):gsub("^Base%.", "")
	text = text:gsub("_", " ")
	text = text:gsub("(%a)([%w']*)", function(first, rest)
		if not first or first == "" then
			return rest or ""
		end
		return string.upper(first) .. string.lower(rest or "")
	end)
	return text ~= "" and text or "?"
end

--- Busca texto vanilla por clave (sin lanzar excepción ni devolver la clave cruda).
---@param key string|nil
---@return string|nil
function GlobalStorageSiK.I18n.tryGetText(key)
	if not key or key == "" or type(getText) ~= "function" then
		return nil
	end
	local ok, value = pcall(getText, key)
	if ok and value and value ~= "" and value ~= key then
		return value
	end
	return nil
end

--- Busca nombre de moveable / sprite en traducciones vanilla.
---@param shortName string
---@return string|nil
local function moveableDisplayName(shortName)
	if not shortName or shortName == "" or type(getText) ~= "function" then
		return nil
	end
	local keys = {
		"Moveables_" .. shortName,
		"IGUI_Moveables_" .. shortName,
	}
	for i = 1, #keys do
		local ok, value = pcall(getText, keys[i])
		if ok and value and value ~= "" and value ~= keys[i] then
			return value
		end
	end
	return nil
end

--- Nombre estable por tipo (sin variaciones de instancia: botellas, contenido, etc.).
---@param fullType string|nil
---@return string
function GlobalStorageSiK.I18n.typeDisplayName(fullType)
	if not fullType or fullType == "" then
		return "?"
	end
	if getItemNameFromFullType then
		local ok, name = pcall(getItemNameFromFullType, fullType)
		if ok and name and name ~= "" and name ~= fullType then
			return name
		end
	end
	local hasScript = false
	local smEarly = getScriptManager and getScriptManager()
	if smEarly and smEarly.getItem then
		local okScript, script = pcall(function()
			return smEarly:getItem(fullType)
		end)
		hasScript = okScript and script ~= nil
	end
	if instanceItem and hasScript then
		local ok, item = pcall(instanceItem, fullType)
		if ok and item then
			if item.getName then
				local okName, itemName = pcall(function()
					return item:getName()
				end)
				if okName and itemName and itemName ~= "" and itemName ~= fullType then
					return itemName
				end
			end
			if item.getDisplayName then
				local okDisp, dispName = pcall(function()
					return item:getDisplayName()
				end)
				if okDisp and dispName and dispName ~= "" and dispName ~= fullType then
					return dispName
				end
			end
		end
	end
	local sm = getScriptManager and getScriptManager()
	if sm and sm.getItem then
		local okItem, script = pcall(function()
			return sm:getItem(fullType)
		end)
		if okItem and script then
			if script.getDisplayName then
				local ok, name = pcall(function()
					return script:getDisplayName()
				end)
				if ok and name and name ~= "" and name ~= fullType then
					return name
				end
			end
			if script.getName then
				local ok, name = pcall(function()
					return script:getName()
				end)
				if ok and name and name ~= "" and name ~= fullType then
					return name
				end
			end
		end
	end
	local shortName = fullType:match("^[^.]+%.(.+)$") or fullType
	local moveable = moveableDisplayName(shortName)
	if moveable and not GlobalStorageSiK.I18n.isLowQualityDisplayName(moveable) then
		return moveable
	end
	local humanized = GlobalStorageSiK.I18n.humanizeToken(shortName)
	if humanized and humanized ~= "" and not GlobalStorageSiK.I18n.isLowQualityDisplayName(humanized) then
		return humanized
	end
	if shortName ~= fullType then
		return shortName
	end
	return fullType
end

--- Detecta nombres de instancia basura (códigos internos, no nombres de jugador).
---@param name string|nil
---@return boolean
function GlobalStorageSiK.I18n.isLowQualityDisplayName(name)
	if not name or name == "" then
		return true
	end
	local trimmed = name:match("^%s*(.-)%s*$") or name
	if #trimmed <= 2 then
		return true
	end
	-- Patrones tipo "A C 01 68", "X Y 12 34" (códigos de mobiliario vanilla).
	if trimmed:match("^%u%s+%u%s+%d+") or trimmed:match("^%u%u?%s+%u%u?%s+%d+") then
		return true
	end
	if trimmed:match("^[%u%d%s%.%-_]+$") and not trimmed:find("%l") and #trimmed <= 24 then
		return true
	end
	return false
end

--- Nombre desde instancia viva (escaneo / cliente).
---@param item InventoryItem|nil
---@param fullType string|nil
---@return string|nil
function GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType)
	if not item then
		return nil
	end
	local typ = fullType
	if not typ and item.getFullType then
		local okType, value = pcall(function()
			return item:getFullType()
		end)
		if okType then
			typ = value
		end
	end
	if item.getCustomName then
		local okCustom, custom = pcall(function()
			return item:getCustomName()
		end)
		if okCustom and custom and custom ~= "" and not GlobalStorageSiK.I18n.isLowQualityDisplayName(custom) then
			return custom
		end
	end
	if item.getName then
		local okName, name = pcall(function()
			return item:getName()
		end)
		if okName and name and name ~= "" and name ~= typ
			and not GlobalStorageSiK.I18n.isLowQualityDisplayName(name) then
			return name
		end
	end
	if item.getDisplayName then
		local okDisp, disp = pcall(function()
			return item:getDisplayName()
		end)
		if okDisp and disp and disp ~= "" and disp ~= typ
			and not GlobalStorageSiK.I18n.isLowQualityDisplayName(disp) then
			return disp
		end
	end
	return nil
end

--- Nombre legible de un ítem según idioma del cliente (estable por fullType).
---@param fullType string|nil
---@param fallback string|nil
---@return string
function GlobalStorageSiK.I18n.itemDisplayName(fullType, fallback)
	if not fullType then
		return fallback or "?"
	end
	local stable = GlobalStorageSiK.I18n.typeDisplayName(fullType)
	if stable and stable ~= "" and stable ~= fullType
		and not GlobalStorageSiK.I18n.isLowQualityDisplayName(stable) then
		return stable
	end
	if fallback and fallback ~= "" and fallback ~= fullType
		and not GlobalStorageSiK.I18n.isLowQualityDisplayName(fallback) then
		return fallback
	end
	if stable and stable ~= "" and not GlobalStorageSiK.I18n.isLowQualityDisplayName(stable) then
		return stable
	end
	return fullType or "?"
end

--- Categoría legible estilo inventario vanilla (p. ej. Arma - Hacha).
---@param fullType string|nil
---@param fallback string|nil
---@param subFallback string|nil
---@return string
function GlobalStorageSiK.I18n.itemCategoryDisplay(fullType, fallback, subFallback, gsSubKeysStr)
	if GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.resolve then
		return GlobalStorageSiK.ItemTaxonomy.resolve(fullType, {
			category = fallback,
			subCategory = subFallback,
			gsSubKeysStr = gsSubKeysStr,
		}).fullLabel
	end
	return fallback or "—"
end

--- Texto buscable de una fila de ítem (idioma del cliente + inglés del servidor + fullType).
---@param row table|nil
---@return string
function GlobalStorageSiK.I18n.itemSearchHaystack(row)
	if not row then
		return ""
	end
	local fullType = row.fullType or ""
	local parts = {}
	local seen = {}

	local function addPart(text)
		if not text or text == "" then
			return
		end
		local key = string.lower(text)
		if seen[key] then
			return
		end
		seen[key] = true
		parts[#parts + 1] = text
	end

	local locName = GlobalStorageSiK.I18n.typeDisplayName(fullType)
	addPart(locName)
	if GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.resolve then
		local tax = GlobalStorageSiK.ItemTaxonomy.resolve(fullType, row)
		addPart(tax.fullLabel)
		addPart(tax.mainLabel)
		addPart(tax.subLabel)
	else
		local locCat = GlobalStorageSiK.I18n.itemCategoryDisplay(fullType, row.category, row.subCategory)
		addPart(locCat)
	end
	addPart(row.displayName)
	addPart(row.category)
	addPart(row.subCategory)
	addPart(fullType)
	local shortName = fullType:match("^[^.]+%.(.+)$")
	if shortName and shortName ~= fullType then
		addPart(shortName)
	end

	return string.lower(table.concat(parts, " "))
end

--- Filtra filas de ítems por consulta (cliente: nombres localizados + inglés).
---@param rows table[]
---@param query string|nil
---@return table[]
function GlobalStorageSiK.I18n.filterItemRows(rows, query)
	if not query or query == "" then
		return rows
	end
	local q = string.lower(query)
	local filtered = {}
	for i = 1, #rows do
		local row = rows[i]
		if string.find(GlobalStorageSiK.I18n.itemSearchHaystack(row), q, 1, true) then
			filtered[#filtered + 1] = row
		end
	end
	return filtered
end
