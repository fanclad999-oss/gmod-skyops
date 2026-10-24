# Прогон заданий артиллерии вне игры

Заглушки API GMod (`gmod_mock.lua`) и сценарий на 4 задания (`test_missions.lua`) с
настоящей баллистикой `arty/core`. Нужен LuaJIT (тот же Lua, что в GMod).

    mkdir -p core && for f in sh_grid sh_firecomp sv_ballistics; do
      git show origin/claude/project-thread-t23cpq:lua/skyops/arty/core/$f.lua > core/$f.lua; done
    luajit test_missions.lua <путь к репозиторию>

В конце печатает `ALL OK`.
