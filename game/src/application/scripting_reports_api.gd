class_name ScriptingReportsApi
extends ScriptingApiBase
## The script functions that give the values of the report windows: the
## Population, Industry and Neighbors windows, the newspaper and the amounts
## of the Budget window. These windows draw their content, thus a script
## cannot read it from their controls. See docs/scripting.md.

@warning_ignore_start("integer_division")

const Budget = preload("res://src/simulation/economy/budget_phase.gd")
const Bonds = preload("res://src/simulation/economy/bond_command.gd")
# the script names of the industries, in Sc2IndustryLayout order
const INDUSTRY_KEYS: PackedStringArray = [
	"steelMining", "textiles", "petrochemical", "food", "construction", "automotive",
	"aerospace", "finance", "media", "electronics", "tourism",
]
# the script names of the budget records, in Sc2BudgetLayout order
const BUDGET_KEYS: PackedStringArray = [
	"residential", "commercial", "industrial", "ordinances", "bonds", "police", "fire", "health", "school", "college",
	"road", "highway", "bridge", "rail", "subway", "tunnel",
]
# the map edge of each neighbor, by (slot - compass rotation); see CityNeighbors.SIDE_HIGH_X
const NEIGHBOR_EDGES: PackedStringArray = ["x-max", "y-max", "x-min", "y-min"]
const CREDIT_RATINGS: PackedStringArray = ["AAA", "AA", "A", "B", "C", "D", "F"]


func handlers() -> Dictionary[String, Callable]:
	return {
		"city.demographics": _demographics,
		"city.industry": _industry,
		"city.neighbors": _neighbors,
		"city.newspapers": _newspapers,
		"city.newspaper": _newspaper,
		"budget.report": _budget_report,
	}


# the values of the Population window: { population, workforcePercent,
# workforceLifeExpectancy, workforceEducation, ages: [{ age, population, lifeExpectancy, education }] }
func _demographics(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var data := PopulationWindowControl.snapshot(app.document_state.city)

	if not data.ok:
		return fail("Cannot read the population: %s." % data.error)

	var ages := []

	for cohort in data.cohorts:
		ages.append({
			"age": cohort.age_start, "population": cohort.population, "lifeExpectancy": cohort.life_expectancy,
			"education": cohort.education_quotient,
		})

	return {
		"population": data.total_population, "workforcePercent": data.workforce_percent,
		"workforceLifeExpectancy": data.workforce_life_expectancy, "workforceEducation": data.workforce_education_quotient,
		"ages": ages,
	}


# the values of the Industry window: [{ key, name, ratio, taxRate, demand }]
func _industry(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var data := IndustryWindowControl.snapshot(app.document_state.city)

	if not data.ok:
		return fail("Cannot read the industries: %s." % data.error)

	var result := []

	for industry in IndustryWindowControl.INDUSTRY_COUNT:
		result.append({
			"key": INDUSTRY_KEYS[industry], "name": IndustryWindowControl.INDUSTRY_NAMES[industry],
			"ratio": data.ratios[industry], "taxRate": data.tax_rates[industry], "demand": data.demands[industry],
		})

	return result


# the values of the Neighbors window: { name, population, nationalPopulation,
# neighbors: [{ name, population, edge }] }. edge is the side of the map
func _neighbors(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var data := SimNationWindowControl.snapshot(app.document_state.city)

	if not data.ok:
		return fail("Cannot read the neighbors: %s." % data.error)

	var neighbors := []

	for neighbor in data.neighbors:
		neighbors.append({
			"name": SimNationWindowControl.neighbor_name(neighbor.name_index), "population": neighbor.population,
			"edge": NEIGHBOR_EDGES[(neighbor.index - data.compass) & 3],
		})

	return {
		"name": data.city_name, "population": data.display_population,
		# the window shows the stored number with three zeros
		"nationalPopulation": data.national_population * 1000,
		"neighbors": neighbors,
	}


# the names of the papers of the Newspaper menu
func _newspapers(_arguments: Array) -> Variant:
	if not need_city():
		return null

	return NewspaperDialog.newspaper_titles(app.document_state.city, app.document_state.current_document)


# the paper that shows: { title, date, price, stories: [{ headline, article }],
# weather, opinion, extra }. Null when no paper shows
func _newspaper(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var dialog := app.city_dialogs.newspaper_dialog if app.city_dialogs != null else null

	if dialog == null or not dialog.visible:
		return null

	var page := dialog.page
	var stories := []

	for slot in page.headlines.size():
		stories.append({"headline": page.headlines[slot], "article": page.articles[slot] if slot < page.articles.size() else ""})

	return {
		"title": page.title_text, "date": page.date_text, "price": page.price_text,
		"stories": stories,
		"weather": {"heading": page.weather_heading, "headline": page.weather_headline, "article": page.weather_article},
		"opinion": {"heading": page.opinion_heading, "headline": page.opinion_headline, "article": page.opinion_article},
		"extra": page.extra_stories.map(func(story: NewspaperContent.ExtraStory) -> Dictionary:
			return {"headline": story.headline, "article": story.article}),
	}


# the amounts of the Budget window for the stored rates: { year, yearEnd,
# recordedMonths, funds, yearToDate, estimate, yearEndFunds, lines, bonds }.
# A line: { key, name, group, rate, yearToDate, estimate, months }. An
# amount is positive for income and negative for a cost
func _budget_report(_arguments: Array) -> Variant:
	if not need_city():
		return null

	var city := app.document_state.city
	var report := BudgetReport.capture(city, Budget.funding_values(city))

	if report.funding.is_empty():
		return fail("Cannot read the budget.")

	var groups := {}

	for group in BudgetReport.GROUPS.size():
		for id: int in BudgetReport.GROUPS[group]:
			groups[id] = BudgetReport.GROUP_NAMES[group]

	var lines := []

	for id in Budget.BUDGET_COUNT:
		lines.append({
			"key": BUDGET_KEYS[id], "name": BudgetReport.NAMES[id], "group": groups.get(id, ""), "rate": report.funding[id],
			"yearToDate": report.year_to_date[id], "estimate": report.estimated[id], "months": report.history[id],
		})

	var terms := BudgetReport.bond_terms(city)
	var rates := []

	for index in terms.count:
		rates.append(city.document.misc_u32(Bonds.MISC_BOND_RATES + index * 4) & 0xffff)

	return {
		"year": city.current_year(), "yearEnd": report.year_end, "recordedMonths": report.actual_months,
		"funds": report.funds, "yearToDate": report.ytd_cash, "estimate": report.estimated_cash,
		"yearEndFunds": BudgetReport.wrap_i32(report.funds + (report.ytd_cash if report.year_end else report.estimated_cash)),
		"lines": lines,
		"bonds": {
			"count": terms.count, "outstanding": terms.count * Bonds.BOND_VALUE, "rates": rates,
			"credit": CREDIT_RATINGS[terms.credit], "bankRate": terms.federal, "nextRate": terms.federal + 1,
			"cityValue": terms.city_value * 1000,
		},
	}
