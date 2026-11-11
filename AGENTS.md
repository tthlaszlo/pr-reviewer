# AI Buddy — projekt- és fejlesztési szabályok

## Munka megkezdése

- A tervezés és a szabályok egyeztetése önmagában nem engedély a fejlesztés megkezdésére.
- Fejlesztést csak a felhasználó kifejezett kérésére kezdj. Addig kizárólag az aktuálisan kért tervezési vagy dokumentációs feladatot végezd el.
- Tartsd be az aktuális kérés határait; ne kezdj el előre későbbi funkciókat megvalósítani.

## Fejlesztési és futtatási környezet

- A fejlesztés helyben, Docker-konténerekben történjen.
- Legyen Docker Compose-fájl, amellyel a helyi környezet egyszerűen indítható és leállítható.
- A fejlesztési parancsok és tesztek Dockerben is futtathatók legyenek; a szükséges lépéseket dokumentáld.
- Az éles termék a Sevalla platformra kerül. Az alkalmazás és a konténeres futtatási konfiguráció kialakításakor ezt vedd figyelembe.

## Kötelező design system

- Minden felületi tervezés és fejlesztés előtt olvasd el a [Focus design systemet](docs/DESIGN_SYSTEM.md), és kövesd az ott rögzített szabályokat.
- Az elfogadott designirány a **Focus**. Az alapértelmezett megjelenés világos; az alkalmazás külső keretének lekerekítése 15 px.
- Új képernyők, komponensek, állapotok és placeholderek is ezt a design systemet használják. Új elemeknél a dokumentált tokeneket és mintákat bővítsd, ne vezess be párhuzamos vizuális stílust.
- A designirányt és az elfogadott alapbeállításokat csak a felhasználó kifejezett kérésére változtasd meg. A jóváhagyott változtatásokat a design system dokumentációjában is vezesd át.

## Git és pull requestek

- GitHub-repó: https://github.com/tthlaszlo/pr-reviewer
- Minden fejlesztés külön branchen és külön pull requestben készüljön.
- Fejlesztési változtatást ne pusholj közvetlenül a `main` ágra.
- A `main` ágba csak stabil, tesztelt és ellenőrzött változtatás kerülhet, pull requesten keresztül.

## Tesztelés

- Minden megvalósított működés legyen tesztekkel lefedve.
- A tesztek a működési követelményeket, a releváns hibakezelést és a szélső eseteket ellenőrizzék.
- Hibajavításhoz készüljön a hibát reprodukáló regressziós teszt.
- A változtatáshoz tartozó teszteket és ellenőrzéseket futtasd le, az eredményüket pedig jelezd az átadáskor.
- Sikertelen vagy el nem végzett ellenőrzést ne állíts be sikeresnek.

## Termék és jelenlegi hatókör

- A termék neve AI Buddy; hosszabb távon több fejlesztői tool közös munkafelülete. Az első tool a PR-reviewk részleges automatizálását támogatja.
- A PR-lista a felhasználónak személyesen, illetve a csapatain keresztül érkező review-kéréseket fogja össze.
- A kért csoportok: még nem adott reviewt; már adott reviewt és a PR várakozik; újra meghívták reviewra.
- A review részletes működését és beállításait, az AI-agenteket, az eredményoldalt és a GitHubra posztolást később tervezzük és valósítjuk meg. Ezekhez egyelőre ne jelenjen meg külön menüpont.
- A későbbi cél a saját Claude- vagy ChatGPT-előfizetések használata specialist agentekkel; az integráció részletei még nincsenek véglegesítve.
- A korábbi technológiai és GitHub-bejelentkezési javaslatokat ne kezeld automatikusan végleges döntésként.

- A Pull requests oldal két aloldala: a személyes/csapatos review-kérések és a felhasználó saját nyitott PR-jei. A három review-csoport az első aloldalon marad.
