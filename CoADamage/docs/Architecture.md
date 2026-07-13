# Architecture

Combat events are parsed by `Core/CombatLog.lua`. Player state is captured by `Data/Stats.lua`. `Data/Experiment.lua` groups observations whenever gear, buffs, or target identity changes. `Data/Database.lua` persists raw observations, while `Analysis/Analysis.lua` performs calculations. UI modules only display results.
