class_name ScriptingBudgetApi
extends ScriptingApiBase
## The `budget` functions of scripts: tax rates, department funding, the
## automatic budget, ordinances and bonds. They follow the rules of the
## Budget and Ordinances windows. See docs/scripting.md.

@warning_ignore_start("integer_division")

const Budget = preload("res://src/simulation/economy/budget_phase.gd")
const Bonds = preload("res://src/simulation/economy/bond_command.gd")
# script names of the budget records, in Sc2BudgetLayout order
const TAXES := {"residential": Sc2BudgetLayout.RESIDENTIAL, "commercial": Sc2BudgetLayout.COMMERCIAL,
	"industrial": Sc2BudgetLayout.INDUSTRIAL}
const FUNDING := {"police": Sc2BudgetLayout.POLICE, "fire": Sc2BudgetLayout.FIRE, "health": Sc2BudgetLayout.HEALTH,
	"school": Sc2BudgetLayout.SCHOOL, "college": Sc2BudgetLayout.COLLEGE, "road": Sc2BudgetLayout.ROAD,
	"highway": Sc2BudgetLayout.HIGHWAY, "bridge": Sc2BudgetLayout.BRIDGE, "rail": Sc2BudgetLayout.RAIL,
	"subway": Sc2BudgetLayout.SUBWAY, "tunnel": Sc2BudgetLayout.TUNNEL}
const INDUSTRY_KEYS := ScriptingReportsApi.INDUSTRY_KEYS
# the limits of the Budget window
const MAXIMUM_TAX := 22
const MAXIMUM_FUNDING := 100
# the ordinance names that scripts use, in OrdinanceIds order
const ORDINANCE_KEYS := [
	"salesTax", "incomeTax", "legalizedGambling", "parkingFines", "volunteerFire", "publicSmokingBan", "freeClinics",
	"juniorSports", "proReading", "antiDrug", "cprTraining", "neighborhoodWatch", "touristAdvertising",
	"businessAdvertising", "cityBeautification", "annualCarnival", "energyConservation", "nuclearFreeZone",
	"homelessShelter", "pollutionControls",
]


func handlers() -> Dictionary[String, Callable]:
	return {
		"budget.info": _info,
		"budget.set": _set_budget,
		"budget.ordinances": _ordinances,
		"budget.setOrdinance": _set_ordinance,
		"budget.issueBond": _bond.bind("issue"),
		"budget.repayBond": _bond.bind("repay"),
	}


# { taxes, funding, industryTaxes, autoBudget, bonds }
func _info(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var values := Budget.funding_values(app.document_state.city)

	return {
		"taxes": _named(values, TAXES),
		"funding": _named(values, FUNDING),
		"industryTaxes": _industry_taxes(),
		"autoBudget": app.document_state.city.auto_budget_enabled(),
		"bonds": app.document_state.city.document.misc_u32(Bonds.MISC_BONDS),
	}


# the tax rate of each industry, as the Industry window shows it: { textiles: 0, ... }
func _industry_taxes() -> Dictionary:
	var data := IndustryWindowControl.snapshot(app.document_state.city)
	var result := {}

	for industry in INDUSTRY_KEYS.size():
		result[INDUSTRY_KEYS[industry]] = data.tax_rates[industry] if data.ok else 0

	return result


# the industry of a script key or of a name of the Industry window, or -1
static func _industry_index(name: String) -> int:
	for industry in INDUSTRY_KEYS.size():
		if name.to_lower() in [INDUSTRY_KEYS[industry].to_lower(), IndustryWindowControl.INDUSTRY_NAMES[industry].to_lower()]:
			return industry

	return -1


static func _named(values: PackedInt32Array, names: Dictionary) -> Dictionary:
	var result := {}

	for name: String in names:
		result[name] = values[names[name]] if names[name] < values.size() else 0

	return result


# changes the named taxes and funding: { taxes: { residential: 9 }, funding: { police: 80 },
# industryTaxes: { textiles: 5 }, autoBudget }. The industry `all` sets each industry
func _set_budget(arguments: Array) -> Variant:
	if not need_city():
		return null

	if app.simulation_state.annual_budget_pending:
		return fail("The yearly budget is open. Close it first.")

	var changes: Variant = argument(arguments, 0, {})

	if not changes is Dictionary:
		return fail("budget.set takes an object such as { taxes: { residential: 8 } }.")

	var values := Budget.funding_values(app.document_state.city)

	for group: Array in [["taxes", TAXES, MAXIMUM_TAX], ["funding", FUNDING, MAXIMUM_FUNDING]]:
		var requested: Variant = changes.get(group[0], {})

		if not requested is Dictionary:
			return fail("%s must be an object." % group[0])

		for name: String in requested:
			var names: Dictionary = group[1]

			if not names.has(name):
				return fail("Unknown %s entry %s. It must be one of: %s." % [group[0], name, ", ".join(names.keys())])

			var value: Variant = requested[name]

			if not is_number(value) or int(value) < 0 or int(value) > int(group[2]):
				return fail("%s.%s must be a number from 0 to %d." % [group[0], name, group[2]])

			values[names[name]] = int(value)

	var industry_taxes: Variant = changes.get("industryTaxes", {})

	if not industry_taxes is Dictionary:
		return fail("industryTaxes must be an object.")

	for name: String in industry_taxes:
		var rate: Variant = industry_taxes[name]

		if name != "all" and _industry_index(name) < 0:
			return fail("Unknown industry %s. It must be all or one of: %s." % [name, ", ".join(INDUSTRY_KEYS)])

		if not is_number(rate) or int(rate) < 0 or int(rate) > IndustryTaxCommand.MAXIMUM_INDUSTRY_TAX:
			return fail("industryTaxes.%s must be a number from 0 to %d." % [name, IndustryTaxCommand.MAXIMUM_INDUSTRY_TAX])

	var auto_budget := bool(changes.get("autoBudget", app.document_state.city.auto_budget_enabled()))
	var stored := Budget.set_funding(app.document_state.city, values, auto_budget)

	if not stored.ok:
		return fail("Cannot save the budget: %s." % stored.error)

	# `all` first, thus a named industry can differ from it
	for name: String in (["all"] if industry_taxes.has("all") else []) + industry_taxes.keys().filter(
			func(key: String) -> bool: return key != "all"):
		var changed := IndustryTaxCommand.set_tax_rate(
			app.document_state.city, maxi(_industry_index(name), 0), int(industry_taxes[name]), name == "all")

		if not changed.ok:
			return fail("Cannot save the industry tax rates: %s." % changed.error)

	if app.city_dialogs != null and app.city_dialogs.industry_window != null:
		app.city_dialogs.industry_window.refresh_city(app.document_state.city)

	app.interface.refresh_details()
	app.scripting.emit_budget_changed()

	return _info([])


# every ordinance: { key, name, category, enabled, cost }. cost is the yearly amount
func _ordinances(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var snapshot := OrdinanceCommand.snapshot(app.document_state.city)

	if not snapshot.ok:
		return fail("Cannot read the ordinances: %s." % snapshot.error)

	var result := []

	for id in OrdinanceIds.COUNT:
		result.append({
			"key": ORDINANCE_KEYS[id],
			"name": OrdinanceCommand.NAMES[id],
			"category": OrdinanceCommand.CATEGORY_NAMES[mini(id / 4, OrdinanceCommand.CATEGORY_NAMES.size() - 1)],
			"enabled": snapshot.flags & (1 << id) != 0,
			"cost": snapshot.item_amounts[id] if id < snapshot.item_amounts.size() else 0,
		})

	return result


# setOrdinance(key or name, enabled)
func _set_ordinance(arguments: Array) -> Variant:
	if not need_city():
		return null

	var value := str(argument(arguments, 0, ""))
	var id := -1

	for index in OrdinanceIds.COUNT:
		if value.to_lower() in [str(ORDINANCE_KEYS[index]).to_lower(), str(OrdinanceCommand.NAMES[index]).to_lower()]:
			id = index

	if id < 0:
		return fail("Unknown ordinance %s. budget.ordinances() lists them." % value)

	var result := OrdinanceCommand.set_enabled(app.document_state.city, id, bool(argument(arguments, 1, true)))

	if not result.ok:
		return fail("Cannot change the ordinance: %s." % result.error)

	if result.changed:
		app.reports.on_ordinances_changed()

	return result.flags & (1 << id) != 0


# issues or repays one $10,000 bond, with the confirmation of the Budget window
func _bond(_arguments: Array, action: String) -> Variant:
	if not need_city():
		return null

	var city := app.document_state.city
	var result := Bonds.issue(city, Bonds.CONFIRMATION_CONFIRMED) if action == "issue" else Bonds.repay(city, Bonds.CONFIRMATION_CONFIRMED)

	if not result.ok:
		return fail("Cannot %s a bond: %s." % [action, result.error])

	if result.status not in ["issued", "repaid"]:
		return fail("The bond was not %s: %s." % ["issued" if action == "issue" else "repaid", result.status.replace("_", " ")])

	app.interface.refresh_details()

	return {"bonds": city.document.misc_u32(Bonds.MISC_BONDS), "rate": result.rate, "funds": city.funds()}
