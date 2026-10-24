# Прогон контрбатарейной борьбы вне игры

Сценарий `test_counter.lua` гоняет `arty/counter` с настоящей баллистикой `arty/core` и
заданиями `arty/missions` на заглушках GMod из `tools/arty-harness/gmod_mock.lua` (PR #9).

    cd tools/arty-harness            # там gmod_mock.lua и core/ (см. его README)
    luajit ../counter-harness/test_counter.lua <репозиторий> <папка arty/missions> [seed]

Проверяет: САУ, которая стоит и стреляет, засекают и накрывают (урон растёт с каждым
залпом); САУ, отъехавшая на 300 м после засечки, остаётся целой, залп ложится на старую
позицию; разведанную батарею противника можно подавить; при `skyops_arty_counter 0`
ничего не считается, батарея убирается вместе с заданием. В конце печатает `ALL OK`.
