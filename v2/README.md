# snake-tests

A simple snake game to try my 
[ECS with builtin rollback](https://github.com/Sandalmoth/scethy).

- Space to rollback 10 frames.
- Arrow keys to steer.

Currently, there's a bug where it crashes if you die by running into yourself, probably relates
to reference counting in the ECS, but it's hard to track down. Note the use of a component for
the snake head with a virtual update functino.
