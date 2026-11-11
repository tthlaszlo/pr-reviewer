# Focus — AI Buddy design system

Állapot: elfogadott designirány, 2026. november 11.

Ez a dokumentum az AI Buddy felületének kötelező vizuális alapja. Minden új képernyő, komponens és placeholder ezt kövesse. A design dokumentálása nem engedély az alkalmazás fejlesztésének megkezdésére.

## Elfogadott megjelenés

- Designirány: **Focus · fejlesztői**.
- Alapértelmezett téma: **világos**, nem automatikus rendszertéma.
- Az alkalmazás külső keretének lekerekítése: **15 px**. Ez nem minden belső komponens lekerekítése.
- Karakter: kompakt, nyugodt, tartalomközpontú fejlesztői munkafelület.
- Színvilág: semleges grafitszürkék, visszafogott indigó/lila kiemeléssel.
- Finom szegélyek, kevés dekoráció, minimális árnyékhasználat.
- A PR-lista az elsődleges felület; az információ hierarchiáját térközzel, tipográfiával és elválasztókkal alakítsuk ki.

## Színtokenek

A világos értékek az elfogadott Focus mintából származnak. A sötét párértékek a mintában bemutatott alternatív témát őrzik meg; nem változtatják meg a világos alapértelmezést, és nem teszik a témaváltó megvalósítását az aktuális feladat részévé.

| Szemantikus token | Világos | Sötét | Használat |
| --- | --- | --- | --- |
| `background` | `#F9F9FC` | `#141418` | Fő munkaterület |
| `surface` | `#FFFFFF` | `#19191F` | Emelt felületek, menük |
| `sidebar` | `#F0F0F6` | `#111115` | Navigáció és visszafogott háttér |
| `text` | `#24232E` | `#E9E8F0` | Elsődleges szöveg |
| `text-muted` | `#696775` | `#A29FAD` | Metaadat és kiegészítő szöveg |
| `border` | `#E5E4ED` | `#303039` | Finom elválasztók |
| `accent` | `#7760DC` | `#7760DC` | Fő művelet, aktív jelölés |
| `accent-soft` | `#EFEBFC` | `#2B2440` | Halvány kijelölési háttér |
| `accent-text` | `#6048BD` | — | Kiemelt kis szöveg és link világos felületen; AA-kontraszthoz sötétített indigó |
| `focus` | `#6048BD` | — | Billentyűzetfókusz 2 px körvonallal, 3 px eltartással |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Kitöltött kiemelt gomb szövege |
| `success` | `#287756` | `#80CBA9` | Sikeres állapot |
| `warning` | `#986316` | `#DFB574` | Figyelmet igénylő állapot |
| `warning-surface` | `#FCF1DE` | `#3A2F1F` | Figyelmeztetés háttere |

Az implementáció központi szemantikus tokeneket használjon; a komponensekben ne ismétlődjenek ad hoc hexértékek. Új hiba-, fókusz- vagy egyéb szemantikus színt központilag kell meghatározni, a kontraszt ellenőrzésével. A kiemelőszínt ne használjuk korlátlanul apró szövegeken: a konkrét előtér–háttér párnak is olvashatónak kell lennie.

## Tipográfia

- Elsődleges betűcsalád: Inter, rendszer sans-serif tartalékkal.
- Kód, technikai azonosítók és billentyűparancsok: rendszer monospace.
- Normál szöveg: 400-as súly; címek és hangsúlyos sorok: 500–600.
- Oldalcím: körülbelül 26 px, tömör hierarchiával.
- Alapszöveg: 14 px; PR-cím: 13–14 px.
- Metaadatok és komponensfeliratok megvalósítási célmérete: 12 px. A sűrű mintanézet kis feliratait ne kicsinyítsük tovább.
- A hosszú PR-cím törhessen több sorba; alapvető információ ne csak tooltipből legyen elérhető.
- A számokhoz szükség szerint tabuláris számjegyeket használjunk.

## Térközök és geometria

- Alap térközskála: 4, 8, 12, 16, 24, 32 px.
- Asztali munkaterület belső térköze: jellemzően 24–28 px.
- Navigációs sáv: kompakt, a mintában körülbelül 176 px széles; a végleges feliratokhoz igazítható.
- PR-sor: körülbelül 16 px függőleges térköz, tartalomfüggő magassággal.
- Elválasztók: 1 px, a `border` tokennel.
- Külső alkalmazáskeret: 15 px lekerekítés.
- Gombok, mezők és navigációs elemek: jellemzően 6 px lekerekítés.
- Kis státuszjelölők: körülbelül 5 px lekerekítés.
- Árnyékot csak rétegzett elemeknél, például menünél vagy párbeszédablaknál használjunk, ha a rétegek elkülönítéséhez szükséges.

## Alap elrendezés

Asztali nézetben bal oldali navigáció és jobb oldali munkaterület jelenjen meg.

A bal oldali sáv tartalma a mintában: termékazonosító, munkatér, aktív navigáció és felhasználói kapcsolat. A fő munkaterület hierarchiája: helyzetjelző, oldalcím és helyi művelet, review-csoportok, szűrési információ, PR-lista, szinkronállapot.

A navigációban a halvány kiemelési háttér jelzi az aktív helyet. Az alkalmazás fő felületén ne jelenjen meg böngészőablakot utánzó dekoráció vagy a designminta tokenbemutató lábléce: ezek csak a vizuális összehasonlítás részei voltak.

## PR-lista és csoportok

A Pull requests navigáció két aloldala: **Review requests** (személyes és csapatos review-kérések), illetve **My pull requests** (a felhasználó saját nyitott PR-jei). Mindkettő külön URL-lel és aktív navigációs jelöléssel rendelkezik. A három review-csoport csak a Review requests aloldalon jelenik meg. A Publishing, Results, AI agents és Review settings menüpontok nem jelennek meg.

A három kért csoport:

1. Még nem reviewztam.
2. Reviewztam · várakozik.
3. Újra meghívtak.

Ezek kompakt tabokként jelenjenek meg, számlálóval. Az aktív tabot kiemelt alsó vonal és szöveges állapot jelölje.

Egy PR-sor elemei:

- PR-állapotikon.
- Elsődleges cím.
- Másodlagos sorban repository, PR-szám, szerző és szükség szerint változtatási adatok.
- Megkülönböztetett személyes vagy csapatos review-kérés.
- Időadat és a releváns állapot szövegesen.

A sorok között finom elválasztók legyenek. Kerüljük a különálló, nagy kártyákat minden egyes PR körül. A designminta repositorynevei, PR-jei, időadatai és számlálói szemléltető adatok; nem termékkövetelmények és nem valós integrációs adatok.

## Komponensek és viselkedés

| Elem | Focus megjelenés |
| --- | --- |
| Elsődleges gomb | Kiemelőszínű kitöltés, kontrasztos felirat, rövid műveletnév |
| Másodlagos gomb | Semleges felület és finom szegély |
| Navigáció | Kompakt sorok, ikon és felirat, halvány aktív háttér |
| Tab | Visszafogott alapállapot, aktív alsó vonal, opcionális számláló |
| Beviteli mező | Semleges felület, finom szegély, látható címke és fókusz |
| Státuszcímke | Kis méretű, szöveges, visszafogott háttérrel |
| Ikon | Egységes, vonalas ikoncsalád, jellemzően 16 px; a mintában Lucide |
| Placeholder | Őszinte leírás a későbbi funkcióról; működést nem színlelő vezérlők |

A képernyőnkénti műveletek számát a tényleges feladat indokolja. Az aktuális hatókörön kívüli review-beállításokat, agenteket, eredményeket és posztolást ne jelenítsük meg a navigációban; ezek későbbi funkciók.

## Állapotok

- A review állapota, az AI-futtatás állapota és egy találat súlyossága külön fogalom; ne kapjanak összetéveszthető jelölést.
- Szín mellett mindig legyen szöveg vagy egyértelmű ikon.
- Személyes és csapatos meghívás külön szöveges jelzést kapjon.
- Betöltés, üres lista, GitHub-kapcsolat hiánya, hiányzó jogosultság és hálózati hiba külön állapot legyen.
- Ismeretlen vagy még be nem töltött darabszámot ne mutassunk nullának.
- Nem működő placeholder gomb ne keltsen működő műveletre vonatkozó ígéretet.

## Reszponzivitás és hozzáférhetőség

- Keskeny nézetben a navigáció tömöríthető, de az elérhetősége és a vezérlők hozzáférhető neve maradjon meg.
- A PR-sorok metaadatai és jobb oldali jelölései törjenek új sorba; a cím ne szoruljon olvashatatlan oszlopba.
- A vezérlők billentyűzettel kezelhetők legyenek, jól látható fókuszállapottal.
- Szöveges kontraszt: WCAG AA, normál szövegnél legalább 4,5:1. Az állapotok ne kizárólag színen alapuljanak.
- Érintőképernyőn a vezérlők effektív célterülete legalább 44 × 44 px legyen.
- Az interaktív komponensek aktív, kiválasztott, tiltott és hibaállapota vizuálisan és szemantikusan is legyen következetes.

## Következetesség és módosítás

- Új felület a meglévő tokeneket, komponenseket és mintákat használja.
- Ha új komponens vagy token szükséges, azt ebbe a rendszerbe illesztve dokumentáljuk.
- A Focus irányt, a világos alapértelmezést és a 15 px-es külső lekerekítést csak kifejezett felhasználói kérésre változtassuk meg.
- A felhasználó által jóváhagyott módosításokat ebben a dokumentumban is vezessük át.
- A design system nem dönt technológiai keretrendszerről, és nem bővíti automatikusan a fejlesztés funkcionális hatókörét.

## Bejelentkezési oldal

A `/login` önálló, világos Focus felület, 15 px-es külső kerettel. Asztalon rövid termékbemutató és szegélyes belépőkártya jelenik meg; mobilon a kártya az elsődleges. A bemutató címe 32–46 px, a kártya címe 22 px. A bejelentkezési módok kizárólag Google és GitHub, külön, legalább 48 px magas gombokkal; nincs jelszavas, e-mailes vagy vendégbelépés. A Google G jelének négy márkaszíne kizárólag a szolgáltató logójában használható, nem képez új felületi színpalettát.

A munkafelület navigációja bejelentkezés előtt nem látható. A még nem konfigurált szolgáltató gombja tiltott, szöveges elérhetőségi magyarázattal. A betöltés, a megszakított/sikertelen belépés és az elérhetőségi hiba külön visszajelzést kap. A Google-belépés és a tool GitHub-kapcsolata külön fogalom; a bejelentkezett Google-fiókhoz a PR-toolban külön Connect GitHub művelet tartozik.
