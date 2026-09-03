# Snacke 🐍

A snake game with the roles reversed: **you are the food.**

The computer plays a hungry snake that chases the nearest meal — usually you. Survive as long as you can, or bait the snake into trapping itself.

## How to Play

- **Move with your mouse.** You step one cell at a time toward the cursor.
- **Grab the food item** and throw it to the snake to score points — every bite makes it longer.
- **Watch out.** If the snake's head reaches you, it's game over.
- **Trap the snake** so it can't move, and you win.

### Power-Up

Once the snake grows to 1/3 of the board, a power-up spawns:

- **You** collect it → the snake is cut in half.
- **The snake** eats it first → it simply teleports elsewhere.

### Scoring

```
(Difficulty × Time Survived) + (Food Thrown × Food Multiplier) + (Snake Length × Length Multiplier)
```

The snake speeds up over time (time-based level-ups) and with its length. Faster difficulty = bigger multipliers.

### Difficulty

| Mode | Snake Speed | Target Survival |
|--------|-------------|-----------------|
| Easy | Slower start, gentler speed-ups | ~10 min |
| Medium | Normal | ~5 min |
| Hard | Normal, brutal pace | ~1 min |

Difficulty is set in **Settings** before you start.

### Leaderboard

Enter your name on the Profile screen — your score is saved to the local top 10.

## Controls

- **Mouse** — move / pick up / throw food
- **Mouse buttons** — navigate menus

## Credits

- **Engine:** [Godot 4](https://godotengine.org)
- **Art, SFX & Music:** [Kenney](https://kenney.nl) (CC0 assets)
- **Profile music:** "Ending" from *Retro Game Music Pack* by [Juhani Junkala](https://opengameart.org/users/subspaceaudio) (CC0, via [OpenGameArt](https://opengameart.org/content/5-chiptunes-action))
- **Font:** Peaberry

Have fun — and don't get eaten. 🍎
