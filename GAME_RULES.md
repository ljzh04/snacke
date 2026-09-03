# GAME_RULES.md
- This is a classic game of snake with a reversed role twist.
- You (the player) is the food. 
- The computer will play as the snake. 
- The goal is to survive as long as possible or get the highest score possible.

- The game starts with three elements. A computer controlled snake, A player controlled food, and a randomly placed food item.

- You (the player) is mouse-controlled. 
- You can move in 4 directions, per tick. North, South, East, West. 
- You can take and throw the food item to the snake which will be counted as an eaten food and increases its length.
- Easy: The snake will move at a slower initial speed and speed-up transitions are less frequent. (Ideal is around 10 minutes play time until death; or 2 minute for testing)
- Medium: The snake will move at a fixed normal average initial speed and normal speed-up transitions. (Ideal is around 5 minutes play time until death; or 1 minute for testing)
- Hard: The snake will move at a fixed normal average initial speed and normal speed-up transitions. (Ideal is around  minutes play time until death; or around 25 seconds for testing)

- Scores are calculated as (Difficulty Multiplier * Time Elapsed) + (Food Thrown * Food Thrown Difficulty Multiplier) + (Snake Length * Length Difficulty Multiplier) 

- The snake will chase the closest food, either food item or player. 
- The snake can only move forwards, or left and right. 
- The snake will try to avoid getting itself trapped as much as possible.
- The snake will increase its chase speed as time passes based on difficulty and length. Capped at a fixed value (minimum move duration of 0.04s).

- Level-ups (which speed up the snake) are time-only — no minimum snake length is required. The time threshold scales with the current level, so the game gets progressively harder to stay alive and speed up the snake.

- Power-up: Once the snake reaches 1/3 of the total board grid size in length, a power-up item spawns on a free cell. When the snake head collects it (or the player walks into it), the snake is immediately halved in size. Only one power-up appears at a time; a new one spawns once the previous is consumed and the length threshold is met again.


# Ideas
- A simple snake-themed main menu with a simple title + play icon button + settings(audio) + exit. Leaderboards are accessible from the profile screen.
- Opening cutscene slide out transition, shows player in zoomed position, fades in 'Survive' in red text, slowly zooms out, then start game after max zoom


- Screens: 
1 main menu -> play / settings / exit
2 profile -> enter name -> play game (difficulty chosen in settings)
3 game end -> profile screen (leaderboard + session stats)
4 settings -> difficulty / volume / mute

- Audio: click SFX on all buttons, SFX for food eaten / level up / game over, looping menu and gameplay music (CC0 from Kenney).
- Backgrounds: layered scrolling geometric patterns (circle, square, triangle) with staggered diagonal rows, varying sizes, and random diagonal drift direction per menu — no parallax mouse tracking.