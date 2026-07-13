# CoADamage

A theorycrafting addon for **Project Ascension: Conquest of Azeroth** (WoW 3.3.5a).

CoADamage is inspired by the classic DRDamage addon but is designed specifically for Conquest of Azeroth's custom classes, abilities, and combat mechanics.

Rather than relying on manually entered spell formulas, CoADamage observes combat, records player stats, and analyzes the collected data to estimate how abilities scale.

---

## Project Goals

- Record every damaging spell cast
- Capture player stats at the time of each attack
- Organize observations into controlled experiments
- Discover spell scaling automatically
- Estimate:
  - Attack Power coefficients
  - Spell Power coefficients
  - Weapon damage scaling
  - Buff and debuff modifiers
- Display estimated damage information in spell tooltips
- Provide an open-source research platform for the Conquest of Azeroth community

---

## Current Features

- Combat log parser
- Damage recording
- Critical hit tracking
- Player stat snapshots
- Spell database
- `/coa stats`
- `/coa inspect`
- Experimental analysis engine

---

## Planned Features

### Version 0.5

- Automatic experiment detection
- Gear fingerprinting
- Buff fingerprinting
- Talent fingerprinting
- Controlled experiment tracking

### Version 0.6

- Statistical analysis
- Outlier detection
- Confidence scoring
- Correlation analysis

### Version 0.7

- Automatic coefficient estimation
- AP scaling
- SP scaling
- Weapon damage scaling
- Buff modifier detection

### Version 1.0

- Tooltip integration
- Live damage estimation
- Research mode
- Export and import experiment data
- Community data sharing

---

## Commands

```text
/coa stats
```

Displays all recorded spells.

```text
/coa inspect <SpellID>
```

Displays detailed information for a recorded spell.

```text
/coa analyze <SpellID>
```

Runs the current analysis engine on a spell.

---

## Development Philosophy

The project is divided into independent modules.

```
Combat Log
        │
        ▼
Snapshot Manager
        │
        ▼
Experiment Manager
        │
        ▼
Database
        │
        ▼
Analysis Engine
        │
        ▼
UI / Tooltip
```

Each module has one responsibility.

This makes the addon easier to maintain, extend, and test.

---

## Long-Term Vision

The long-term goal is to create a community-driven theorycrafting platform capable of reverse engineering the custom spell mechanics used in Project Ascension: Conquest of Azeroth.

Instead of manually entering formulas, the addon will learn them through statistical analysis of real combat data.

---

## Contributing

Contributions are welcome.

Future contributors should follow these guidelines:

- Keep modules focused on a single responsibility.
- Avoid global variables.
- Prefer readable code over clever code.
- Document new systems.
- Test changes on Conquest of Azeroth before submitting.

---

## Credits

Created by Travis Hensley

Developed with assistance from ChatGPT.

Inspired by the original DRDamage addon and the Project Ascension community.