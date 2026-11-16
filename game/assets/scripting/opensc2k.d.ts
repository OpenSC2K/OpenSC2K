// TypeScript declarations of the OpenSC2K script API: the globals of the
// console runtime and of each mod. Copy this file into a mod folder for the
// completion and the checks of TypeScript and of editors such as VS Code.
// game/assets/scripting/api.js and native/core/scripting/src/prelude.js define the
// API; docs/scripting.md and docs/mods.md describe it. The API is new: names
// and fields can change.
//
// scripting_types_test checks that each member of api.js and each game event is here.

/** A tile position. The API also takes `[x, y]` or `(x, y)`. */
interface TilePoint {
  x: number;
  y: number;
}

type TileArgument = TilePoint | [number, number];

/** A date of the city. A month has 25 days. `age` counts the days from the founding. */
interface CityDate {
  year: number;
  month: number;
  day: number;
  age: number;
}

/** The demand of each zone kind, from -2000 to 2000. */
interface Demand {
  residential: number;
  commercial: number;
  industrial: number;
}

interface CityInfo {
  name: string;
  mayor: string;
  /** The number of tiles on each map edge. */
  size: number;
  funds: number;
  population: number;
  foundingYear: number;
  /** The weather that the status bar shows, such as `Chilly`. */
  weather: string;
  difficulty: number;
  scenario: boolean;
  /** The file of the city, or an empty text. */
  path: string;
  date: CityDate;
  demand: Demand;
}

type DataMapName = 'traffic' | 'pollution' | 'landValue' | 'crime' | 'police' | 'fire' | 'populationDensity' | 'growth';

/** The value of each data map at a tile. */
type TileData = Record<DataMapName, number>;

/** The stored values of a tile. */
interface Tile {
  x: number;
  y: number;
  altitude: number;
  waterAltitude: number;
  terrain: number;
  building: number;
  zone: number;
  underground: number;
  overlay: number;
  water: boolean;
  saltWater: boolean;
  powered: boolean;
  powerable: boolean;
  watered: boolean;
  piped: boolean;
  traffic: number;
  data: TileData;
  /** The name of the structure on the tile, or an empty text. */
  name: string;
  /** The name of the zone, or an empty text. */
  zoneName: string;
  /** The character of the tile on the surface layer of `city.textMap`. */
  symbol: string;
}

/** A rectangle of tiles. */
interface TileArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** What the Query tool shows for a tile. */
interface QueryInfo {
  x: number;
  y: number;
  title: string;
  /** The text of the query window. */
  text: string;
  kind: string;
  zone: string;
  density: string;
  building: number;
  altitude: number;
  landValue: number;
  crime: string;
  pollution: string;
  traffic: number;
  powered: boolean;
  watered: boolean;
  underground: string;
  lines: string[];
  flags: string[];
  /** The moving objects on the tile. */
  things: string[];
}

/** The stored values of an area. The value of the tile (x + i, y + j) is at index `j * width + i`. */
interface CityRegion extends TileArea {
  building: number[];
  zone: number[];
  terrain: number[];
  underground: number[];
  altitude: number[];
  /** 1 for a water tile. */
  water: number[];
  powered: number[];
  watered: number[];
}

type TextLayer = 'surface' | 'zones' | 'underground' | 'altitude' | 'power' | 'water';

/** An area as text. Character `i` of `rows[j]` is the tile (x + i, y + j). */
interface TextMap extends TileArea {
  layer: TextLayer;
  /** The meaning of each character. */
  legend: Record<string, string>;
  rows: string[];
}

interface FoundTile {
  x: number;
  y: number;
  building: number;
  name: string;
}

interface Census {
  tiles: number;
  /** Structure name -> number of tiles. */
  structures: Record<string, number>;
  /** Zone name -> number of tiles. */
  zones: Record<string, number>;
  water: number;
  powered: number;
  unpowered: number;
}

/** The values of the Population window. An age group covers five years. */
interface Demographics {
  population: number;
  /** The percentage of the residents who are of working age. */
  workforcePercent: number;
  workforceLifeExpectancy: number;
  /** The education quotient of the work force. */
  workforceEducation: number;
  ages: { age: number; population: number; lifeExpectancy: number; education: number }[];
}

type IndustryKey = 'steelMining' | 'textiles' | 'petrochemical' | 'food' | 'construction' | 'automotive'
  | 'aerospace' | 'finance' | 'media' | 'electronics' | 'tourism';

/** One row of the Industry window. */
interface Industry {
  key: IndustryKey;
  name: string;
  /** The size of the industry in the city, as the Ratios chart shows it. */
  ratio: number;
  /** The tax rate of the industry in percent. `budget.set({ industryTaxes })` changes it. */
  taxRate: number;
  /** The national demand for the industry. */
  demand: number;
}

/** The values of the Neighbors window. */
interface Neighbors {
  name: string;
  /** The population of the city with its arcologies. */
  population: number;
  nationalPopulation: number;
  /** `edge` is the side of the map of the neighbor. The name `Ocean` has no city. */
  neighbors: { name: string; population: number; edge: 'x-max' | 'y-max' | 'x-min' | 'y-min' }[];
}

interface NewspaperReport {
  heading: string;
  headline: string;
  article: string;
}

/** The newspaper that shows. */
interface Newspaper {
  title: string;
  date: string;
  price: string;
  /** The first story is the lead story. */
  stories: { headline: string; article: string }[];
  weather: NewspaperReport;
  opinion: NewspaperReport;
  extra: { headline: string; article: string }[];
}

interface PngExportOptions {
  /** The image shows only these tiles, and the game draws only them. Without it: the whole city. */
  area?: TileArea;
  /** The size of the tiles. The default is `'small'`. */
  size?: 'small' | 'medium' | 'large';
  /** The default is `'city'`. */
  view?: 'city' | 'underground';
  signs?: boolean;
  movingThings?: boolean;
  transparent?: boolean;
}

interface ImageFile {
  path: string;
  width: number;
  height: number;
  /** City images only: the place of the image, in pixels, in the picture of the whole city. */
  origin?: { x: number; y: number };
}

interface DataMap {
  name: DataMapName;
  /** The number of values on each edge of the map. */
  size: number;
  /** The number of tiles on each edge of one value. */
  scale: number;
  /** The values, column by column: `values[x * size + y]`. */
  values: number[];
  /** The value at a tile. */
  at(x: number | TileArgument, y?: number): number;
}

type GraphName =
  | 'City Size' | 'Residents' | 'Commerce' | 'Industry' | 'Traffic' | 'Pollution' | 'Value' | 'Crime' | 'Power %'
  | 'Water %' | 'Health' | 'Education' | 'Unemployment' | 'GNP' | "Nat'n Pop." | 'Fed Rate';

type GraphPeriod = 'year' | 'decade' | 'century';

/** A moving object of the city. */
interface Thing {
  id: number;
  type: number;
  name: string;
  x: number;
  y: number;
  state: number;
}

interface Taxes {
  residential: number;
  commercial: number;
  industrial: number;
}

/** The funding of each department, in percent. */
interface Funding {
  police: number;
  fire: number;
  health: number;
  school: number;
  college: number;
  road: number;
  highway: number;
  bridge: number;
  rail: number;
  subway: number;
  tunnel: number;
}

interface BudgetInfo {
  taxes: Taxes;
  funding: Funding;
  /** The tax rate of each industry, from 0 to 20. */
  industryTaxes: Record<IndustryKey, number>;
  autoBudget: boolean;
  bonds: number;
}

interface BudgetChanges {
  taxes?: Partial<Taxes>;
  funding?: Partial<Funding>;
  /** The key `all` sets each industry. A key can also be a name of the Industry window. */
  industryTaxes?: Partial<Record<IndustryKey | 'all', number>>;
  autoBudget?: boolean;
}

/** One line of the Budget window. An amount is positive for income and negative for a cost. */
interface BudgetLine {
  key: keyof Taxes | keyof Funding | 'ordinances' | 'bonds';
  name: string;
  /** The row of the Budget window that holds the line, such as `Roads & transit`. */
  group: string;
  /** The tax rate or the funding in percent. */
  rate: number;
  yearToDate: number;
  /** The estimate for the full year. */
  estimate: number;
  /** The amount of each month, January first. Months after `recordedMonths` are estimates. */
  months: number[];
}

/** The amounts of the Budget window for the stored rates. */
interface BudgetReportInfo {
  year: number;
  /** True while the yearly budget waits for its settlement. */
  yearEnd: boolean;
  recordedMonths: number;
  funds: number;
  /** The cash flow of the year until now. */
  yearToDate: number;
  /** The cash flow of the full year. */
  estimate: number;
  yearEndFunds: number;
  lines: BudgetLine[];
  bonds: {
    count: number;
    outstanding: number;
    /** The interest rate of each bond in percent, the oldest first. */
    rates: number[];
    /** From `AAA` to `F`. */
    credit: string;
    bankRate: number;
    /** The interest rate of the next bond. */
    nextRate: number;
    cityValue: number;
  };
}

interface Ordinance {
  key: string;
  name: string;
  category: string;
  enabled: boolean;
  /** The yearly amount. A tax ordinance has income. */
  cost: number;
}

interface BondResult {
  bonds: number;
  rate: number;
  funds: number;
}

type SpeedName = 'Paused' | 'Turtle' | 'Llama' | 'Cheetah' | 'African Swallow';

interface Disaster {
  id: number;
  name: string;
}

interface ToolInfo {
  group: number;
  subtool: number;
  groupName: string;
  name: string;
  cost: number;
}

interface ToolListItem extends ToolInfo {
  available: boolean;
}

type ViewMode =
  | 'city' | 'underground' | 'density' | 'growth' | 'traffic' | 'pollution' | 'crime' | 'police_power' | 'fire_power'
  | 'land_value' | 'water' | 'power' | 'height';

/** A window that shows, or a full-screen panel of the game such as the main menu. */
interface UiWindow {
  /** The node path of the window, or `'main'` for the game window. */
  id: string;
  type: string;
  title: string;
  /** The message of a dialog. */
  text: string;
  /** True when the windows below take no input. */
  modal: boolean;
  /** True when the simulation waits while the window shows. */
  blocking: boolean;
  focused: boolean;
  rect: ScreenRect;
  /** The texts of the buttons. */
  buttons: string[];
  /** The items of a popup menu. */
  items?: UiItem[];
}

/** A rectangle in pixels of the game window. */
interface ScreenRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** A position in pixels of the game window. */
interface ScreenPoint {
  x: number;
  y: number;
}

type ScreenArgument = ScreenPoint | [number, number];

interface UiItem {
  index: number;
  text: string;
  disabled?: boolean;
  /** The id of a menu item. */
  id?: number;
  checked?: boolean;
  separator?: boolean;
  submenu?: UiItem[];
  /** The depth, the cells and the selection of a tree row. */
  depth?: number;
  cells?: string[];
  selected?: boolean;
}

/** A control that takes input. */
interface UiControl {
  /** The node path of the control. */
  id: string;
  kind: 'button' | 'check' | 'option' | 'menu' | 'text' | 'number' | 'tabs' | 'list' | 'tree' | 'custom';
  /** The class of the control. */
  type: string;
  /** The node name. */
  name: string;
  /** The label, or the tooltip. */
  text: string;
  tooltip?: string;
  value?: boolean | number | string | string[];
  disabled?: boolean;
  min?: number;
  max?: number;
  step?: number;
  items?: UiItem[];
  rect: ScreenRect;
  /** True when `ui.image` can save the picture of the control. */
  image?: true;
  /**
   * Values of a control that draws its content. The canvas of the SCURK editor gives
   * `{ spriteWidth, spriteHeight, zoom, tool, colorIndex, brushSize, origin, end }`: `origin` is the
   * corner of sprite pixel (0, 0) and `end` the far corner of the last one, in pixels of the game window.
   */
  data?: Record<string, unknown>;
}

/** A control by its id, its text or its node name; or by a text in one window. */
type UiTarget = string | { id: string } | { text: string; window?: string };

interface UiMenu {
  text: string;
  disabled: boolean;
  items: UiItem[];
}

/** An action of a key or a menu. */
interface GameAction {
  id: string;
  label: string;
  category: string;
  scope: string;
  kind: string;
}

interface GameState {
  screen: 'startup' | 'main-menu' | 'new-city' | 'terrain-editor' | 'city' | 'scurk';
  assetsReady: boolean;
  /** True while a city loads or saves. */
  busy: boolean;
  /** The text of the status bar: the result or the error of the last action. */
  status: string;
  /** The windows that show, without the game window. */
  windows: Pick<UiWindow, 'id' | 'type' | 'title' | 'text' | 'blocking' | 'buttons'>[];
  city: {
    name: string;
    mayor: string;
    size: number;
    funds: number;
    population: number;
    path: string;
    date: CityDate;
    demand: Demand;
  } | null;
  speed?: SpeedName;
  /** Why the simulation waits, or an empty text. */
  suspended?: string;
  tool?: ToolInfo;
  disaster?: Disaster | null;
  view?: { mode: ViewMode; zoom: number; rotation: number; center: TilePoint };
}

type TerrainFeature =
  | 'meander' | 'delta' | 'peninsula' | 'crossing' | 'branch' | 'rejoin' | 'bay' | 'island' | 'islands' | 'plateau'
  | 'ridge' | 'valley' | 'rolling' | 'basin' | 'canyon' | 'cliffs' | 'lake' | 'lakes';

interface NewCityOptions {
  name?: string;
  mayor?: string;
  difficulty?: 'easy' | 'medium' | 'hard' | 1 | 2 | 3;
  year?: 1900 | 1950 | 2000 | 2050;
  /** The tiles on each map edge. The default is 128. */
  size?: 16 | 32 | 64 | 128 | 256 | 384 | 512 | 640 | 1024 | 2048 | 4096;
  /** True makes a city that the original game opens: 128 tiles, SC2 format. */
  sc2?: boolean;
  ocean?: boolean;
  river?: boolean;
  /** The amounts of hills, water and trees, from 0 to 47. */
  hills?: number;
  water?: number;
  trees?: number;
  features?: TerrainFeature[];
  /** The same seed and options make the same terrain. */
  seed?: number;
  /** True stays in the terrain editor. Press "Done" to found the city. */
  edit?: boolean;
  /** True drops the unsaved changes of the open city. */
  discard?: boolean;
}

interface GameFiles {
  cities: string[];
  scenarios: string[];
  saved: string[];
  savedFolder: string;
  /** The autosaves of the last minutes, in the temporary folder. */
  autosaves: string[];
}

/** What the game plays now. A program cannot hear the game. */
interface AudioState {
  /** `track` is -1 and `name` is empty when no track was started. */
  music: { enabled: boolean; playing: boolean; paused: boolean; track: number; name: string };
  /** `loop` is the id of the sound that repeats, or -1. */
  sound: { enabled: boolean; loop: number };
}

/** The info.json fields of a mod. */
interface ModInfo {
  id: string;
  name: string;
  version: string;
  description: string;
  main: string;
  author: string;
  email: string;
  website: string;
  license: string;
  gameVersion: string;
  dependencies: string[];
}

/** A file or a folder in the mod folder. */
interface FileEntry {
  name: string;
  type: 'file' | 'directory' | 'other';
  size: number;
  /** The time of the last change, in milliseconds since 1970. */
  modified: number;
}

/** A JSON value, as `game.storage` and events copy it. */
type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };

// ------------------------------------------------------------------ events

interface ToolAppliedDetail {
  tool: ToolInfo;
  start: TilePoint;
  finish: TilePoint;
  dragged: boolean;
  tiles: number;
  changed: boolean;
  cancelled: boolean;
  command: string;
  cost: number;
  message: string;
}

/** The fields of each game event, by type. */
interface GameEventMap {
  'city.opened': { name: string; size: number; date: CityDate };
  'city.closed': {};
  'city.saved': { path: string };
  'city.renamed': { name: string };
  'budget.changed': BudgetInfo;
  'sim.speed': { speed: SpeedName };
  'sim.day': { year: number; month: number; day: number; age: number };
  'sim.month': { year: number; month: number };
  'sim.year': { year: number };
  'disaster.beforeStart': { id: number; name: string; x: number; y: number };
  'disaster.started': Disaster;
  'disaster.ended': Disaster;
  news: { type: number; argument: number; name: string };
  notice: { id: number; text: string };
  /** The game asked for sounds, by their ids. The sound settings can drop a sound. */
  sound: { ids: number[] };
  'budget.prompt': {};
  'military.proposal': {};
  'game.over': { type: string; funds: number };
  'tool.selected': { tool: ToolInfo };
  'tool.beforeApply': { tool: ToolInfo; start: TilePoint; finish: TilePoint; dragged: boolean; tiles: number };
  'tool.applied': ToolAppliedDetail;
  'tool.undone': { command: string };
  'view.mode': { mode: ViewMode };
  frame: { delta: number };
  'mod.loaded': { id: string; name: string; version: string };
  'mod.unloaded': { id: string };
}

/** The event object that a listener receives. */
type GameEvent<Detail = {}> = Detail & {
  readonly type: string;
  readonly cancelable: boolean;
  /** True when a listener cancelled a cancelable event. */
  cancelled: boolean;
  /** Stops the action of a cancelable event, such as `tool.beforeApply`. */
  cancel(): void;
  /** The id of the mod that sent an event of `game.emit`, or `'console'`. */
  source?: string;
};

type Listener<Detail> = (event: GameEvent<Detail>) => void;

// ------------------------------------------------------------------ globals

interface Game {
  /** `{ game, godot, quickjs }` version texts. */
  readonly version: { game: string; godot: string; quickjs: string };
  /** The event types of the game and their descriptions. */
  readonly events: Record<keyof GameEventMap, string>;
  /** The info of each mod that runs. */
  readonly mods: ModInfo[];

  /** Calls the listener for each event of the type. `'*'` listens to all events. Returns a function that removes the listener. */
  on<Type extends keyof GameEventMap>(type: Type, listener: Listener<GameEventMap[Type]>, options?: { once?: boolean }): () => boolean;
  on(type: '*', listener: Listener<Record<string, any>>, options?: { once?: boolean }): () => boolean;
  on<Detail = Record<string, any>>(type: string, listener: Listener<Detail>, options?: { once?: boolean }): () => boolean;
  /** Listens to the next event of the type only. */
  once<Type extends keyof GameEventMap>(type: Type, listener: Listener<GameEventMap[Type]>): () => boolean;
  once<Detail = Record<string, any>>(type: string, listener: Listener<Detail>): () => boolean;
  /** Removes a listener. Returns true when it was there. */
  off(type: string, listener: (event: any) => void): boolean;
  listenerCount(type: string): number;
  /**
   * Sends an event to the script listeners of the console and of each mod. Each runtime gets a copy of the
   * detail, with `source`. A mod cannot send a game event. Start the type with the id of your mod.
   */
  emit(type: string, detail?: { [key: string]: JsonValue }): void;
  /** Adds a console command. The handler receives the words after the name, and returns the text to show. */
  command(name: string, description: string, handler: (...words: string[]) => unknown): void;
  /** Shows a message on the status bar. */
  status(text: string): void;
  /** What the game shows now. Call it after an action to see the result and what waits for an answer. */
  state(): GameState;
  /** The actions of the keys and the menus. */
  actions(): GameAction[];
  /** Runs an action as its key does, such as `'window_budget'`. False when it does nothing now. */
  action(id: string): boolean;
  /** Makes the terrain and founds a city, as the New City window does. Console scripts only. */
  newCity(options?: NewCityOptions): GameState;
  /** Opens a city or a scenario file. Console scripts only. */
  open(path: string, options?: { discard?: boolean }): GameState;
  /** Saves the city to a path. Resolves with the path when the file is written. Console scripts only. */
  saveAs(path: string): Promise<string>;
  /** The city files that the game knows. Console scripts only. */
  files(): GameFiles;
  /** What the game plays now: the music track, and if the music and the sounds are on. */
  audio(): AudioState;
  /** Shows the main menu, or with false returns from it to the city. Returns the screen. Console scripts only. */
  mainMenu(show?: boolean): GameState['screen'];
  /** Closes the game. Console scripts only. */
  quit(options?: { discard?: boolean }): true;
  /** The stored settings: `{ section: { key: value } }`. Console scripts only. */
  readonly settings: Record<string, Record<string, unknown>>;
  /** The settings that the game uses now, also those that the file does not hold. The Settings window changes them. Console scripts only. */
  readonly preferences: Record<string, unknown>;
  /** Get or set the debug mode: the Debug menu and the debug tools. Console scripts only. */
  debugMode: boolean;
  /** Resolves after a time in milliseconds. */
  wait(milliseconds: number): Promise<void>;
  /** Resolves after the game drew this many frames. */
  frames(count?: number): Promise<void>;
  /** Resolves when `test()` is true. Rejects after the timeout in milliseconds; the default is 30000. */
  until(test: () => boolean, timeout?: number): Promise<void>;
  /** Values that stay after the game closes. Each mod has its own values. */
  readonly storage: {
    /** The stored value, or the fallback. Give the type for a TypeScript check: `get<Zone[]>('zones', [])`. */
    get<Value = any>(key: string, fallback?: NoInfer<Value>): Value;
    set(key: string, value: JsonValue): true;
    remove(key: string): boolean;
    keys(): string[];
  };
}

interface City {
  readonly loaded: boolean;
  /** A copy of the main city values. */
  info(): CityInfo;
  readonly name: string;
  readonly mayor: string;
  /** The number of tiles on each map edge. */
  readonly size: number;
  readonly population: number;
  readonly date: CityDate;
  readonly demand: Demand;
  /** Get or set the funds. Setting them is a cheat. */
  funds: number;
  /** Adds a positive or negative amount, as a cheat. Returns the new funds. */
  addFunds(amount: number): number;
  /** The stored values of a tile, or null outside the map. */
  tile(x: number | TileArgument, y?: number): Tile | null;
  /** The value of a data map at a tile. */
  data(name: DataMapName, x: number | TileArgument, y?: number): number;
  dataMap(name: DataMapName): DataMap;
  readonly dataMaps: DataMapName[];
  /** A graph history, oldest value first. */
  graph(name: GraphName, period?: GraphPeriod): number[];
  readonly graphs: GraphName[];
  /** Gives the city a new name. Returns the name. */
  rename(name: string): string;
  /** The text of the sign on a tile, or null. */
  sign(x: number | TileArgument, y?: number): string | null;
  /** Places or changes a sign. An empty text removes it. */
  setSign(x: number, y: number, text: string): true;
  /** Every sign of the city. */
  signs(): { x: number; y: number; text: string }[];
  /** The moving objects. */
  things(): Thing[];
  /** Saves the city to its file. Returns the path. */
  save(): string;
  /** True when the city has changes that its file does not have. This compares the whole city; it is slow on a large map. */
  readonly unsaved: boolean;
  /** What the Query tool shows for a tile. */
  query(x: number | TileArgument, y?: number): QueryInfo;
  /** The stored values of an area, or of the whole map. */
  region(x?: number | TileArea, y?: number, width?: number, height?: number): CityRegion;
  /** An area, or the whole map, as text: one character for each tile. */
  textMap(area?: TileArea, layer?: TextLayer): TextMap;
  readonly textLayers: TextLayer[];
  /** The tiles of a structure, by a part of its name or by its stored id. 2000 tiles at most. */
  find(what: string | number, area?: TileArea): FoundTile[];
  /** The number of tiles of each structure and zone in an area, or in the whole map. */
  census(area?: TileArea): Census;
  /** The values of the Population window. */
  demographics(): Demographics;
  /** The values of the Industry window. */
  industry(): Industry[];
  /** The values of the Neighbors window. */
  neighbors(): Neighbors;
  /** The names of the papers of the Newspaper menu. */
  readonly newspapers: string[];
  /** The newspaper that shows, or null. `ui.menu('Newspaper', city.newspapers[0])` opens a paper. */
  newspaper(): Newspaper | null;
  /** Writes an image of the city, or of the tiles of `options.area`, to a PNG file. Resolves when the export ends. Console scripts only. */
  exportPng(path: string, options?: PngExportOptions): Promise<ImageFile>;
}

interface Budget {
  info(): BudgetInfo;
  /** The amounts of the Budget window: each line, the totals and the bonds. */
  report(): BudgetReportInfo;
  readonly taxes: Taxes;
  readonly funding: Funding;
  readonly industryTaxes: Record<IndustryKey, number>;
  /** Changes the named values. Tax rates go from 0 to 22, funding from 0 to 100, industry tax rates from 0 to 20. */
  set(changes: BudgetChanges): BudgetInfo;
  ordinances(): Ordinance[];
  /** Enables or disables an ordinance by its key or its name. Returns the new state. */
  setOrdinance(key: string, enabled?: boolean): boolean;
  /** Issues a $10,000 bond. Throws when the council refuses it. */
  issueBond(): BondResult;
  /** Repays the oldest bond. */
  repayBond(): BondResult;
}

interface Sim {
  /** Get or set the speed, by name or from 1 to 5. */
  speed: SpeedName | number;
  readonly paused: boolean;
  pause(): void;
  /** Selects the speed before the pause. */
  resume(): void;
  /** Runs one day while the game is paused. Returns a report. */
  step(): string;
  /** The active disaster, or null. */
  readonly disaster: Disaster | null;
  /** The disaster names and ids. */
  readonly disasters: Record<string, number>;
  /** Starts a disaster by name or id at a tile, or at the view center. This is a cheat. */
  startDisaster(disaster: string | number, x?: number | TileArgument, y?: number): Disaster;
  /** Ends the active disaster. False without a disaster. */
  endDisaster(): boolean;
  /** Get or set: true turns the random disasters off. */
  noDisasters: boolean;
  /** Runs at the speed until the date, then pauses. */
  runUntil(date: { year: number; month?: number; day?: number }, speed?: SpeedName | number): boolean;
  /** Why the simulation waits now, or an empty text: a prompt, a window that blocks it, the terrain editor. */
  readonly suspended: string;
  /**
   * Pauses the game and runs this many days, as fast as the computer can. Stops early when the simulation
   * must wait; `stopped` tells why. While a disaster is active, the game runs the ticks of the disaster and
   * no days: then `advance` runs 32 ticks and stops with `'disaster: <name>'`.
   */
  advance(days?: number): Promise<{ days: number; date: CityDate; stopped: string }>;
  /** Runs at the speed until the date. Resolves when the game paused there, or when the simulation must wait. */
  runTo(date: { year: number; month?: number; day?: number }, speed?: SpeedName | number): Promise<{ date: CityDate; stopped: string }>;
}

interface Tools {
  list(): ToolListItem[];
  readonly selected: ToolInfo;
  /** Selects a tool by its group and tool name or index, or by one tool or group name. */
  select(group: string | number, tool?: string | number): ToolInfo;
  /** Uses the selected tool as a drag from one tile to another. Without `to`, it is a click. */
  apply(from: TileArgument, to?: TileArgument): ToolAppliedDetail;
  /** Undoes the last edit. False when there is nothing to undo. */
  undo(): boolean;
}

interface View {
  /** The tile at the center of the view. */
  readonly center: TilePoint;
  /** Moves the view to a tile. */
  centerOn(x: number | TileArgument, y?: number): boolean;
  /** Get or set the view. */
  mode: ViewMode;
  readonly modes: ViewMode[];
  /** The zoom in percent. */
  readonly zoom: number;
  zoomIn(): number;
  zoomOut(): number;
  /** The compass rotation, 0 to 3. */
  readonly rotation: number;
  /** A quarter turn, clockwise unless the argument is false. Returns the rotation. */
  rotate(clockwise?: boolean): number;
  /** Get or set: true moves the view to each tile that a script uses a tool on, for a person who watches the game. */
  follow: boolean;
  /** The center of a tile in pixels of the game window. `visible` tells if the map shows it. */
  screenOf(x: number | TileArgument, y?: number): ScreenPoint & { visible: boolean };
  /** The tile at a place of the game window, or null outside the map. */
  tileAt(x: number | ScreenArgument, y?: number): TilePoint | null;
  /** The layers that show. */
  readonly layers: Record<ViewLayer, boolean>;
  /** Shows or hides a layer, as the View menu does. */
  setLayer(name: ViewLayer, shown?: boolean): Record<ViewLayer, boolean>;
}

type ViewLayer =
  | 'buildings' | 'networks' | 'water' | 'trees' | 'signs' | 'vehicles' | 'waterMains' | 'pipes' | 'subways' | 'tunnels';

interface Ui {
  /** A message window with an OK button. The game continues while it shows. */
  alert(text: string, title?: string): void;
  /** Shows a message on the status bar. */
  status(text: string): void;
  /** Plays SOUNDS/<id>.WAV of the sound pack. */
  playSound(id: number): void;
  // The functions below control the interface as the player does. Console scripts only.
  /** The windows that show, the lowest first. The first is the game window, `'main'`; the last takes the input. */
  windows(): UiWindow[];
  /** The controls of a window that take input. Without a window: the top one. */
  controls(window?: string): UiControl[];
  /** The texts that a window shows, top to bottom. */
  texts(window?: string): string[];
  /** Presses a button. A check box changes its state. */
  press(target: UiTarget): true;
  /** Sets a text field, a number or a check box. `submit` also sends Enter in a text field. */
  set(target: UiTarget, value: string | number | boolean, options?: { submit?: boolean }): true;
  /**
   * Chooses an item by its text or index: an option, a tab, a row of a list or a tree, an item of a menu
   * button, or an item of a popup menu that shows (give the id of its window). `activate` also sends the
   * double click of a list or a tree.
   */
  choose(target: UiTarget, item: string | number | (string | number)[], options?: { activate?: boolean }): true;
  /** The menus of the menu bar with their items. */
  menus(): UiMenu[];
  /** Chooses an item of the menu bar: `ui.menu('File', 'Save City')`. */
  menu(...path: (string | number)[]): true;
  /** Answers a dialog with its OK button. Without a window: the top one. */
  accept(window?: string): true;
  /** Closes a window as its close button does. A dialog takes it as Cancel. */
  close(window?: string): true;
  /** Selects a full path in the file dialog that shows. */
  chooseFile(path: string): true;
  /** The size of the game window in pixels. A headless game draws no image. */
  readonly screen: { width: number; height: number; headless: boolean };
  /** Saves an image of the game window as a PNG file. Without a path: in the screenshots folder of the user data. */
  screenshot(path?: string, options?: { scale?: number }): Promise<ImageFile>;
  /**
   * Saves the picture of a control that draws its content, such as the canvas of the SCURK editor.
   * A headless game can do this. Without a target: the first such control of the top window.
   * `scale` makes each pixel larger, from 1 to 16.
   */
  image(target: UiTarget | undefined, path: string, options?: { scale?: number }): ImageFile;
}

type MouseButtonName = 'left' | 'right' | 'middle' | 'back' | 'forward';

/**
 * Mouse and keyboard input, as the devices of the player send it. Use it for an action that has no function
 * of its own. A position is in pixels of the game window. Console scripts only.
 */
interface GameInput {
  /** The place of the pointer of scripts. */
  readonly position: ScreenPoint;
  move(x: number | ScreenArgument, y?: number): ScreenPoint;
  /** Presses a mouse button at a place, or at the pointer. */
  mouseDown(x?: number | ScreenArgument, y?: number, button?: MouseButtonName): ScreenPoint;
  mouseUp(x?: number | ScreenArgument, y?: number, button?: MouseButtonName): ScreenPoint;
  click(x?: number | ScreenArgument, y?: number, options?: { button?: MouseButtonName; double?: boolean }): ScreenPoint;
  /** A drag from one place to another, one step each frame. */
  drag(from: ScreenArgument, to: ScreenArgument, options?: { button?: MouseButtonName; steps?: number }): Promise<ScreenPoint>;
  /** Turns the mouse wheel. A positive step scrolls down. */
  scroll(steps?: number, x?: number | ScreenArgument, y?: number, options?: { horizontal?: boolean }): ScreenPoint;
  /** Presses and releases a key with its modifiers: `'Ctrl+S'`, `'Escape'`, `'F12'`, `'Shift+Tab'`. */
  key(text: string): true;
  keyDown(text: string): true;
  keyUp(text: string): true;
  /** Types a text into the control with the focus. */
  text(value: string): true;
  /** Releases every mouse button and modifier key that a script holds. */
  release(): true;
}

/** The files of the mod folder. Each path is relative to the folder; a path outside it throws an Error. */
interface ModFiles {
  readText(path: string): string;
  readJSON<Value = JsonValue>(path: string): Value;
  readBytes(path: string): Uint8Array;
  /** Writes text to a file. Makes the missing folders. */
  writeText(path: string, text: string): void;
  appendText(path: string, text: string): void;
  writeJSON(path: string, value: unknown, space?: number | string): void;
  writeBytes(path: string, data: Uint8Array | ArrayBuffer | ArrayBufferView | number[]): void;
  exists(path: string): boolean;
  stat(path: string): FileEntry | null;
  list(path?: string): FileEntry[];
  makeFolder(path: string): void;
  /** Removes a file or a folder. Returns false when nothing was there. */
  remove(path: string, options?: { recursive?: boolean }): boolean;
  rename(from: string, to: string): void;
}

interface Mod {
  readonly id: string;
  readonly name: string;
  readonly version: string;
  /** All fields of info.json. */
  readonly info: Readonly<ModInfo>;
  readonly files: ModFiles;
}

declare const game: Game;
declare const city: City;
declare const budget: Budget;
declare const sim: Sim;
declare const tools: Tools;
declare const view: View;
declare const ui: Ui;
declare const input: GameInput;
/** The mod of this runtime. Only the runtime of a mod has it; the console runtime does not. */
declare const mod: Mod;

/** The text that the console shows for a value. */
declare function inspect(value: unknown, options?: { depth?: number }): string;

// QuickJS-ng has the timers of the game, without the DOM or Node.js types
declare function setTimeout(callback: (...values: any[]) => void, ms?: number, ...values: any[]): number;
declare function setInterval(callback: (...values: any[]) => void, ms?: number, ...values: any[]): number;
declare function clearTimeout(id: number | undefined): void;
declare function clearInterval(id: number | undefined): void;

interface Console {
  log(...values: unknown[]): void;
  info(...values: unknown[]): void;
  debug(...values: unknown[]): void;
  warn(...values: unknown[]): void;
  error(...values: unknown[]): void;
  trace(...values: unknown[]): void;
  dir(value: unknown, options?: { depth?: number }): void;
  assert(condition: unknown, ...values: unknown[]): void;
  count(label?: string): void;
  countReset(label?: string): void;
  time(label?: string): void;
  timeEnd(label?: string): void;
}

declare var console: Console;
