# Monster long-run test

Run the retained visual and locomotion test from the project root:

```sh
godot --path . --script res://src/entities/monster/tests/monster_long_run.gd
```

The default run simulates 3,600 physics frames and writes a screenshot every 300
frames to `user://monster_long_run`. The console records position, planted and
stepping tendrils, encounter state, attack phase, player health, and surface normal.

For a longer run or a custom output directory, place arguments after `--`:

```sh
godot --path . --script res://src/entities/monster/tests/monster_long_run.gd -- \
  --frames=18000 --capture-every=600 --output=/tmp/monster_long_run
```

Add `--cycle-phases` to apply controlled damage at one-third and two-thirds of
the run. This quickly exercises ROAM, ARTILLERY, and NEST in one test.

Add `--contact-test` to place the player briefly against the monster and verify
that close-contact damage is delivered through the correct physics layer.

Add `--front-view` to keep captures at player height in front of the monster.
This is useful for boss silhouette, eye, and attack-telegraph readability checks.

Run the structural combat regression independently:

```sh
godot --headless --path . --script res://src/entities/monster/tests/monster_combat_loop.gd
```

It verifies that two pistol-damaged weakpoints trigger collapse and one exposure
cannot remove more than its configured health cap.

Run the lightweight eye-flock smoke test:

```sh
godot --path . --script res://src/entities/monster/tests/eye_swarm_smoke.gd
```

It spawns a wave, verifies movement and signal-driven neighbour exchange, and
writes `user://eye_swarm_smoke.png` for visual inspection of the model and trails.
