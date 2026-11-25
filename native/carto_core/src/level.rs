//! Dati del livello (`levels/*.json`) e validatore di raggiungibilita'.
//!
//! Il livello e' modellato come una mappa di altezze 2.5D (celle da 25 cm). Un'area e' raggiungibile se
//! esiste un cammino di celle adiacenti dove il dislivello in salita non supera [`MAX_STEP`]; le
//! discese (cadute da un bordo) sono sempre permesse, i vuoti (nessuna superficie) mai.
//! La progressione e' una chiusura a punto fisso: raggiungere un forziere o la leva da' una "chiave"
//! che cambia il livello (il ponte appare, il cancello si apre) e si ricalcola finche' non cambia piu' nulla.
//!
//! E' un modello volutamente semplice: serve a dimostrare le proprieta' di design (niente scorciatoie
//! impreviste, tutto cio' che deve essere raggiungibile lo e'), non a sostituire la fisica del motore.

use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub type V3 = [f32; 3];

/// Dimensione di una cella della griglia, in metri.
pub const CELL: f32 = 0.25;
/// Massimo dislivello in salita tra due celle adiacenti (il robot non salta).
pub const MAX_STEP: f32 = 0.45;
/// Massima differenza di quota per poter interagire con un oggetto (come nel gioco).
pub const INTERACT_DY: f32 = 2.5;

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Deserialize)]
pub struct Solid {
    pub id: String,
    pub min: V3,
    pub max: V3,
    pub mat: String,
    #[serde(default = "yes")]
    pub collide: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Wedge {
    pub id: String,
    pub start: V3,
    pub end: V3,
    pub width: f32,
    pub mat: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Shrine {
    pub pos: V3,
    pub spawn: V3,
    pub radius: f32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StoneProp {
    pub pos: V3,
    pub yaw: f32,
    pub radius: f32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Chest {
    pub id: String,
    pub pos: V3,
    pub yaw: f32,
    pub radius: f32,
    pub grants: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Gate {
    pub min: V3,
    pub max: V3,
    pub opened_by: String,
    pub hint: V3,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Lever {
    pub pos: V3,
    pub radius: f32,
    pub grants: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Bridge {
    pub min: V3,
    pub max: V3,
    pub requires: String,
}

fn guardian() -> String {
    "guardian".to_string()
}

/// Tipi di nemico noti al gioco (`scripts/enemy.gd`).
pub const ENEMY_KINDS: [&str; 3] = ["guardian", "brute", "sentinel"];

#[derive(Debug, Clone, Deserialize)]
pub struct EnemySpawn {
    pub pos: V3,
    #[serde(default = "guardian")]
    pub kind: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Props {
    pub player_start: V3,
    pub shrine: Shrine,
    pub stone: StoneProp,
    pub chests: Vec<Chest>,
    pub gate: Gate,
    pub lever: Lever,
    pub bridge: Bridge,
    pub enemies: Vec<EnemySpawn>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Level {
    pub name: String,
    pub version: u32,
    pub materials: BTreeMap<String, [f32; 3]>,
    pub solids: Vec<Solid>,
    pub wedges: Vec<Wedge>,
    pub props: Props,
}

impl Level {
    pub fn from_json(json: &str) -> Result<Level, String> {
        let level: Level = serde_json::from_str(json).map_err(|e| format!("JSON del livello non valido: {e}"))?;
        level.check_structure()?;
        Ok(level)
    }

    /// Controlli strutturali: id unici, materiali esistenti, scatole ben formate.
    pub fn check_structure(&self) -> Result<(), String> {
        let mut ids = BTreeSet::new();
        for s in &self.solids {
            if !ids.insert(s.id.clone()) {
                return Err(format!("id duplicato: {}", s.id));
            }
            if !self.materials.contains_key(&s.mat) {
                return Err(format!("solido '{}': materiale sconosciuto '{}'", s.id, s.mat));
            }
            for k in 0..3 {
                if s.min[k] >= s.max[k] {
                    return Err(format!("solido '{}': min >= max sull'asse {k}", s.id));
                }
            }
        }
        for (n, e) in self.props.enemies.iter().enumerate() {
            if !ENEMY_KINDS.contains(&e.kind.as_str()) {
                return Err(format!("nemico {n}: tipo sconosciuto '{}'", e.kind));
            }
        }
        for w in &self.wedges {
            if !ids.insert(w.id.clone()) {
                return Err(format!("id duplicato: {}", w.id));
            }
            if !self.materials.contains_key(&w.mat) {
                return Err(format!("rampa '{}': materiale sconosciuto '{}'", w.id, w.mat));
            }
            if w.width <= 0.0 || (w.start[0] == w.end[0] && w.start[2] == w.end[2]) {
                return Err(format!("rampa '{}': geometria degenere", w.id));
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Griglia di altezze
// ---------------------------------------------------------------------------

pub struct Grid {
    pub x0: f32,
    pub z0: f32,
    pub w: usize,
    pub h: usize,
    /// Quota della superficie calpestabile per cella; NaN = vuoto (niente su cui stare).
    pub top: Vec<f32>,
}

impl Grid {
    #[inline]
    pub fn idx(&self, ix: usize, iz: usize) -> usize {
        iz * self.w + ix
    }

    pub fn cell_of(&self, x: f32, z: f32) -> Option<(usize, usize)> {
        let fx = (x - self.x0) / CELL;
        let fz = (z - self.z0) / CELL;
        if fx < 0.0 || fz < 0.0 {
            return None;
        }
        let (ix, iz) = (fx as usize, fz as usize);
        (ix < self.w && iz < self.h).then_some((ix, iz))
    }

    pub fn center(&self, ix: usize, iz: usize) -> (f32, f32) {
        (self.x0 + (ix as f32 + 0.5) * CELL, self.z0 + (iz as f32 + 0.5) * CELL)
    }

    pub fn top_at(&self, x: f32, z: f32) -> Option<f32> {
        let (ix, iz) = self.cell_of(x, z)?;
        let t = self.top[self.idx(ix, iz)];
        (!t.is_nan()).then_some(t)
    }

    #[inline]
    fn walkable(&self, i: usize) -> bool {
        !self.top[i].is_nan()
    }

    /// Si puo' passare da `a` a `b`? (adiacenti) Salita limitata, discesa libera, mai nel vuoto.
    #[inline]
    fn can_step(&self, a: usize, b: usize) -> bool {
        self.walkable(a) && self.walkable(b) && self.top[b] - self.top[a] <= MAX_STEP + 1e-4
    }
}

fn wedge_height(w: &Wedge, x: f32, z: f32) -> Option<f32> {
    let hx = w.end[0] - w.start[0];
    let hz = w.end[2] - w.start[2];
    let len = (hx * hx + hz * hz).sqrt();
    let (dx, dz) = (hx / len, hz / len);
    let (px, pz) = (x - w.start[0], z - w.start[2]);
    let t = (px * dx + pz * dz) / len;
    let lateral = (px * -dz + pz * dx).abs();
    if (0.0..=1.0).contains(&t) && lateral <= w.width * 0.5 {
        Some(w.start[1] + t * (w.end[1] - w.start[1]))
    } else {
        None
    }
}

fn raise(slot: &mut f32, y: f32) {
    // f32::max ignora NaN: la prima superficie trovata sostituisce il "vuoto".
    *slot = slot.max(y);
}

/// Costruisce la griglia per un dato insieme di chiavi (`lantern`, `lever`, ...).
pub fn build_grid(level: &Level, keys: &BTreeSet<String>) -> Grid {
    let (mut minx, mut maxx, mut minz, mut maxz) = (f32::MAX, f32::MIN, f32::MAX, f32::MIN);
    for s in &level.solids {
        minx = minx.min(s.min[0]);
        maxx = maxx.max(s.max[0]);
        minz = minz.min(s.min[2]);
        maxz = maxz.max(s.max[2]);
    }
    let x0 = (minx / CELL).floor() * CELL;
    let z0 = (minz / CELL).floor() * CELL;
    let w = ((maxx - x0) / CELL).ceil() as usize + 1;
    let h = ((maxz - z0) / CELL).ceil() as usize + 1;
    let mut grid = Grid { x0, z0, w, h, top: vec![f32::NAN; w * h] };

    let bridge_on = keys.contains(&level.props.bridge.requires);
    let gate_closed = !keys.contains(&level.props.gate.opened_by);

    for iz in 0..h {
        for ix in 0..w {
            let (x, z) = grid.center(ix, iz);
            let i = grid.idx(ix, iz);
            let mut slot = f32::NAN;
            for s in level.solids.iter().filter(|s| s.collide) {
                if x >= s.min[0] && x <= s.max[0] && z >= s.min[2] && z <= s.max[2] {
                    raise(&mut slot, s.max[1]);
                }
            }
            for wd in &level.wedges {
                if let Some(y) = wedge_height(wd, x, z) {
                    raise(&mut slot, y);
                }
            }
            let b = &level.props.bridge;
            if bridge_on && x >= b.min[0] && x <= b.max[0] && z >= b.min[2] && z <= b.max[2] {
                raise(&mut slot, b.max[1]);
            }
            let g = &level.props.gate;
            if gate_closed && x >= g.min[0] && x <= g.max[0] && z >= g.min[2] && z <= g.max[2] {
                raise(&mut slot, g.max[1]);
            }
            grid.top[i] = slot;
        }
    }
    grid
}

/// Celle raggiungibili partendo dal punto `(x, z)`. Vuoto se il punto non e' su una superficie.
pub fn reach_from(grid: &Grid, x: f32, z: f32) -> Vec<bool> {
    let mut seen = vec![false; grid.w * grid.h];
    let Some((sx, sz)) = grid.cell_of(x, z) else { return seen };
    let start = grid.idx(sx, sz);
    if !grid.walkable(start) {
        return seen;
    }
    seen[start] = true;
    let mut queue = VecDeque::from([(sx, sz)]);
    while let Some((cx, cz)) = queue.pop_front() {
        let a = grid.idx(cx, cz);
        for dz in -1i32..=1 {
            for dx in -1i32..=1 {
                if dx == 0 && dz == 0 {
                    continue;
                }
                let (nx, nz) = (cx as i32 + dx, cz as i32 + dz);
                if nx < 0 || nz < 0 || nx as usize >= grid.w || nz as usize >= grid.h {
                    continue;
                }
                let (nx, nz) = (nx as usize, nz as usize);
                let b = grid.idx(nx, nz);
                if seen[b] || !grid.can_step(a, b) {
                    continue;
                }
                // Niente scorciatoie "tagliando gli angoli" attraverso due ostacoli in diagonale.
                if dx != 0 && dz != 0 {
                    let n1 = grid.idx((cx as i32 + dx) as usize, cz);
                    let n2 = grid.idx(cx, (cz as i32 + dz) as usize);
                    if !grid.can_step(a, n1) || !grid.can_step(a, n2) {
                        continue;
                    }
                }
                seen[b] = true;
                queue.push_back((nx, nz));
            }
        }
    }
    seen
}

/// Un oggetto interattivo e' "raggiunto" se una cella raggiunta sta entro `radius` (in orizzontale)
/// e a quota compatibile: la stessa regola con cui il gioco sceglie l'interattivo piu' vicino.
pub fn item_reached(grid: &Grid, reach: &[bool], pos: V3, radius: f32) -> bool {
    let span = (radius / CELL).ceil() as i32 + 1;
    let Some((cx, cz)) = grid.cell_of(pos[0], pos[2]) else { return false };
    for dz in -span..=span {
        for dx in -span..=span {
            let (ix, iz) = (cx as i32 + dx, cz as i32 + dz);
            if ix < 0 || iz < 0 || ix as usize >= grid.w || iz as usize >= grid.h {
                continue;
            }
            let (ix, iz) = (ix as usize, iz as usize);
            let i = grid.idx(ix, iz);
            if !reach[i] {
                continue;
            }
            let (x, z) = grid.center(ix, iz);
            let d = ((x - pos[0]).powi(2) + (z - pos[2]).powi(2)).sqrt();
            if d <= radius && (grid.top[i] - pos[1]).abs() <= INTERACT_DY {
                return true;
            }
        }
    }
    false
}

// ---------------------------------------------------------------------------
// Analisi della progressione
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Stage {
    /// Chiavi possedute all'inizio di questa fase.
    pub keys: BTreeSet<String>,
    /// Oggetti raggiungibili in questa fase (`shrine`, `stone`, `gate_hint`, `chest:<id>`, `lever`, `enemy:<n>`).
    pub items: BTreeSet<String>,
    pub reachable_cells: usize,
}

#[derive(Debug, Clone)]
pub struct Analysis {
    pub stages: Vec<Stage>,
}

impl Analysis {
    pub fn final_stage(&self) -> &Stage {
        self.stages.last().expect("almeno una fase")
    }

    /// In quale fase (indice) l'oggetto diventa raggiungibile per la prima volta?
    pub fn first_stage_with(&self, item: &str) -> Option<usize> {
        self.stages.iter().position(|s| s.items.contains(item))
    }
}

fn items_in(level: &Level, grid: &Grid, reach: &[bool]) -> BTreeSet<String> {
    let p = &level.props;
    let mut items = BTreeSet::new();
    if item_reached(grid, reach, p.shrine.pos, p.shrine.radius) {
        items.insert("shrine".to_string());
    }
    if item_reached(grid, reach, p.stone.pos, p.stone.radius) {
        items.insert("stone".to_string());
    }
    if item_reached(grid, reach, p.gate.hint, 2.4) {
        items.insert("gate_hint".to_string());
    }
    for c in &p.chests {
        if item_reached(grid, reach, c.pos, c.radius) {
            items.insert(format!("chest:{}", c.id));
        }
    }
    if item_reached(grid, reach, p.lever.pos, p.lever.radius) {
        items.insert("lever".to_string());
    }
    for (n, e) in p.enemies.iter().enumerate() {
        if let Some((ix, iz)) = grid.cell_of(e.pos[0], e.pos[2]) {
            if reach[grid.idx(ix, iz)] {
                items.insert(format!("enemy:{n}"));
            }
        }
    }
    items
}

/// Simula la progressione del giocatore: parte senza chiavi e prende tutto cio' che raggiunge.
pub fn analyze(level: &Level) -> Analysis {
    let mut keys: BTreeSet<String> = BTreeSet::new();
    let mut stages = Vec::new();
    loop {
        let grid = build_grid(level, &keys);
        let ps = level.props.player_start;
        let reach = reach_from(&grid, ps[0], ps[2]);
        let items = items_in(level, &grid, &reach);
        let cells = reach.iter().filter(|r| **r).count();
        let mut gained = BTreeSet::new();
        for c in &level.props.chests {
            if let (Some(k), true) = (&c.grants, items.contains(&format!("chest:{}", c.id))) {
                gained.insert(k.clone());
            }
        }
        if items.contains("lever") {
            gained.insert(level.props.lever.grants.clone());
        }
        stages.push(Stage { keys: keys.clone(), items, reachable_cells: cells });
        let before = keys.len();
        keys.extend(gained);
        if keys.len() == before {
            break;
        }
    }
    Analysis { stages }
}

/// Dal punto `from` si puo' arrivare vicino a `to` (raggio `radius`) con queste chiavi?
pub fn can_reach(level: &Level, keys: &[&str], from: V3, to: V3, radius: f32) -> bool {
    let keys: BTreeSet<String> = keys.iter().map(|k| k.to_string()).collect();
    let grid = build_grid(level, &keys);
    let reach = reach_from(&grid, from[0], from[2]);
    item_reached(&grid, &reach, to, radius)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SLICE: &str = include_str!("../../../levels/slice.json");

    fn slice() -> Level {
        Level::from_json(SLICE).expect("slice.json valido")
    }

    #[test]
    fn slice_json_parses_and_is_well_formed() {
        let l = slice();
        assert_eq!(l.name, "slice");
        assert!(l.solids.len() > 15 && l.wedges.len() == 2);
        assert_eq!(l.props.chests.len(), 2);
        assert_eq!(l.props.enemies.len(), 5);
        let kinds: Vec<&str> = l.props.enemies.iter().map(|e| e.kind.as_str()).collect();
        assert_eq!(kinds, ["guardian", "guardian", "guardian", "sentinel", "brute"]);
    }

    #[test]
    fn unknown_enemy_kind_is_rejected() {
        let mut l = slice();
        l.props.enemies[0].kind = "drago".into();
        assert!(l.check_structure().unwrap_err().contains("tipo sconosciuto"));
    }

    #[test]
    fn malformed_levels_are_rejected() {
        assert!(Level::from_json("{").is_err());
        let mut l = slice();
        l.solids[1].id = l.solids[0].id.clone();
        assert!(l.check_structure().unwrap_err().contains("duplicato"));
        let mut l = slice();
        l.solids[0].mat = "inesistente".into();
        assert!(l.check_structure().unwrap_err().contains("materiale"));
        let mut l = slice();
        l.solids[0].max[1] = l.solids[0].min[1];
        assert!(l.check_structure().unwrap_err().contains("min >= max"));
    }

    #[test]
    fn heights_match_the_game_geometry() {
        // Gli stessi valori che tests/game_test.gd verifica con i raycast della fisica.
        let l = slice();
        let g = build_grid(&l, &BTreeSet::new());
        let near = |x: f32, z: f32, y: f32| {
            let t = g.top_at(x, z).unwrap_or(f32::NAN);
            assert!((t - y).abs() < 0.13, "({x},{z}): atteso {y}, trovato {t}");
        };
        near(5.0, 4.0, 0.0);
        near(0.0, -5.0, 0.5);
        near(0.0, -6.0, 1.0);
        near(0.0, -10.0, 2.0);
        near(0.0, -17.0, 2.0);
        near(7.5, -17.0, 1.0);
        near(8.0, -12.0, 0.0);
        assert!(g.top_at(0.0, -13.5).is_none(), "il vuoto non ha superficie senza lanterna");
        let with = build_grid(&l, &["lantern".to_string()].into());
        assert!((with.top_at(0.0, -13.5).unwrap() - 2.0).abs() < 1e-4, "con la lanterna c'e' il ponte");
    }

    #[test]
    fn progression_is_lantern_then_lever() {
        let a = analyze(&slice());
        assert_eq!(a.stages.len(), 3, "tre fasi: nessuna chiave, lanterna, lanterna+leva");
        assert!(a.stages[0].keys.is_empty());
        assert_eq!(a.stages[1].keys, BTreeSet::from(["lantern".to_string()]));
        assert_eq!(a.stages[2].keys, BTreeSet::from(["lantern".to_string(), "lever".to_string()]));
    }

    #[test]
    fn items_unlock_in_the_intended_order() {
        let a = analyze(&slice());
        for always in ["shrine", "stone", "gate_hint", "chest:lantern", "enemy:0", "enemy:1", "enemy:2", "enemy:3"] {
            assert_eq!(a.first_stage_with(always), Some(0), "{always} deve essere raggiungibile subito");
        }
        assert_eq!(a.first_stage_with("chest:heart"), Some(1), "il cuore richiede la lanterna");
        assert_eq!(a.first_stage_with("lever"), Some(1), "la leva richiede la lanterna");
        assert_eq!(a.first_stage_with("enemy:4"), Some(1), "il bruto sta sulla terrazza: richiede la lanterna");
        // Nessun oggetto e' irraggiungibile alla fine.
        let all: Vec<String> = ["shrine", "stone", "gate_hint", "chest:lantern", "chest:heart", "lever"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        for item in all {
            assert!(a.final_stage().items.contains(&item), "{item} irraggiungibile");
        }
    }

    #[test]
    fn heart_chest_and_lever_are_unreachable_without_the_lantern() {
        let l = slice();
        let start = l.props.player_start;
        let heart = l.props.chests.iter().find(|c| c.id == "heart").unwrap();
        assert!(!can_reach(&l, &[], start, heart.pos, heart.radius));
        assert!(can_reach(&l, &["lantern"], start, heart.pos, heart.radius));
        assert!(!can_reach(&l, &[], start, l.props.lever.pos, l.props.lever.radius));
        // Ipotesi: leva gia' tirata, nessuna lanterna. Il cancello aperto e' una SECONDA entrata alla
        // terrazza (corridoio -> rampa 2), ma nella progressione reale la leva si raggiunge solo con la
        // lanterna (vedi items_unlock_in_the_intended_order), quindi non e' un'aggirabilita'.
        assert!(can_reach(&l, &["lever"], start, heart.pos, heart.radius));
    }

    #[test]
    fn corridor_is_sealed_from_the_courtyard_until_the_lever() {
        let l = slice();
        let start = l.props.player_start;
        let corridor = [8.0, 0.0, -14.0];
        assert!(!can_reach(&l, &[], start, corridor, 1.0));
        // Con la sola lanterna si arriva nel corridoio dall'alto (terrazza -> rampa 2), non dal cancello.
        assert!(can_reach(&l, &["lantern"], start, corridor, 1.0));
        // Il cancello chiuso blocca il passaggio verso il cortile dal lato del corridoio.
        assert!(!can_reach(&l, &[], corridor, start, 1.0), "dal corridoio non si torna al cortile a cancello chiuso");
    }

    #[test]
    fn the_gate_shortcut_loops_back_to_the_shrine_without_the_bridge() {
        let l = slice();
        let terrace_c = [0.0, 2.0, -17.5];
        let shrine = l.props.shrine.pos;
        // Ipotesi: leva tirata, ponte non attivo. Dalla terrazza si scende dalla rampa 2, si attraversa il
        // cancello aperto e si arriva al santuario: la scorciatoia funziona da sola.
        assert!(can_reach(&l, &["lever"], terrace_c, shrine, l.props.shrine.radius));
        // Senza la leva e senza il ponte la terrazza e' un'isola rispetto al cortile (si scende solo nel corridoio).
        assert!(!can_reach(&l, &[], terrace_c, shrine, l.props.shrine.radius));
        // Con il ponte (lanterna) si torna indietro anche senza leva.
        assert!(can_reach(&l, &["lantern"], terrace_c, shrine, l.props.shrine.radius));
    }

    #[test]
    fn validator_catches_a_missing_fence() {
        // Test di mutazione: se si toglie la staccionata, dall'altopiano ci si lascia cadere nel corridoio
        // e si aggira tutto. Il validatore deve accorgersene.
        let original = slice();
        let start = original.props.player_start;
        let corridor = [8.0, 0.0, -14.0];
        assert!(!can_reach(&original, &[], start, corridor, 1.0), "originale: sigillato");
        let mut broken = slice();
        broken.solids.retain(|s| s.id != "fence");
        assert!(can_reach(&broken, &[], start, corridor, 1.0), "senza staccionata il corridoio e' aggirabile");
        let a = analyze(&broken);
        assert_eq!(a.first_stage_with("lever"), Some(0), "senza staccionata la leva e' raggiungibile subito");
    }

    #[test]
    fn validator_catches_an_always_on_bridge() {
        // Mutazione: il ponte "richiede" la chiave "" e simuliamo di averla, cioe' un ponte sempre attivo.
        let mut broken = slice();
        broken.props.bridge.requires = String::new();
        let keys: BTreeSet<String> = [String::new()].into();
        let g = build_grid(&broken, &keys);
        assert!(g.top_at(0.0, -13.5).is_some());
        // Se il ponte fosse sempre attivo, il cuore sarebbe raggiungibile senza lanterna.
        let heart = broken.props.chests.iter().find(|c| c.id == "heart").unwrap().clone();
        assert!(can_reach(&broken, &[""], broken.props.player_start, heart.pos, heart.radius));
    }

    #[test]
    fn a_tall_wall_always_blocks() {
        let l = slice();
        let g = build_grid(&l, &BTreeSet::new());
        let r = reach_from(&g, 0.0, 7.5);
        // Le celle dei muri alti non sono raggiungibili: salirci richiederebbe 5 m di salita.
        let (ix, iz) = g.cell_of(-10.25, 0.0).unwrap();
        assert!(!r[g.idx(ix, iz)]);
        // Fuori dalla mappa non e' raggiungibile nulla.
        assert!(g.cell_of(-100.0, 0.0).is_none());
    }

    #[test]
    fn props_sit_on_walkable_surfaces() {
        let l = slice();
        let g = build_grid(&l, &["lantern".to_string(), "lever".to_string()].into());
        let on_floor = |name: &str, p: V3| {
            let t = g.top_at(p[0], p[2]).unwrap_or_else(|| panic!("{name}: nessuna superficie sotto"));
            assert!((t - p[1]).abs() < 0.3, "{name}: sta a y={} ma il pavimento e' a {t}", p[1]);
        };
        on_floor("player_start", l.props.player_start);
        on_floor("shrine", l.props.shrine.pos);
        on_floor("stone", l.props.stone.pos);
        on_floor("lever", l.props.lever.pos);
        for c in &l.props.chests {
            on_floor(&format!("chest {}", c.id), c.pos);
        }
        for (n, e) in l.props.enemies.iter().enumerate() {
            on_floor(&format!("enemy {n}"), e.pos);
        }
    }
}
