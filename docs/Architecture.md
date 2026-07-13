# CoADamage Architecture

## Goal

Collect combat observations and discover spell scaling through statistical analysis.

---

## Pipeline

Combat Log
    ↓
Snapshot
    ↓
Experiment Manager
    ↓
Database
    ↓
Analysis Engine
    ↓
UI

---

## Responsibilities

### Combat Log

Receives combat events from WoW.

Never performs calculations.

---

### Snapshot

Captures the player's state.

Examples:

- Attack Power
- Spell Power
- Weapon Damage
- Strength
- Agility
- Buffs
- Target

---

### Experiment Manager

Groups observations together when all important conditions match.

Starts a new experiment when gear, buffs, talents, or targets change.

---

### Database

Stores observations.

Never analyzes them.

---

### Analysis

Performs statistical analysis.

Produces coefficients and confidence values.

---

### UI

Displays information.

Never modifies data.