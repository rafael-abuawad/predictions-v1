compile:; vyper ./contracts/*.vy

test:; pytest -v

format:; ruff format .