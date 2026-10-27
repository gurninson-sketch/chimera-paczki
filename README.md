# Chimera Paczki

Autonomiczny kurier dla **głównych skryptów Chimery** w Mudlecie. Wybiera najpierw paczki miejscowe, a po ich wyczerpaniu międzymiastowe poczta → poczta, dostarcza je do NPC i urzędów, obsługuje bramy oraz przeprawy, uczy się potwierdzonych adresatów i zachowuje kurs po rozłączeniu.

## Instalacja i aktualizacje

Pobierz [najnowsze wydanie](https://github.com/gurninson-sketch/chimera-paczki/releases/latest) i plik **Chimera_Paczki.zip**. Ten ZIP zawiera natywny dodatek Chimery; wypakuj go do katalogu profilu Mudleta.

1. W Mudlecie wpisz `/bot stop` i poczekaj na zakończenie trwającej operacji ruchu lub plecaka.
2. Zastąp cały folder `<profil>/chimera_wtyczki/chimera_paczki` folderem z ZIP-a (25 plików Lua).
3. Wpisz `/przeladuj` i zaczekaj na zakończenie ładowania.
4. Sprawdź `/paczki diagnostyka` — wersja 1.5.15. Rozpocznij `/bot paczki` albo kontynuuj zapisany kurs przez `/paczki wznow`.

Dotychczasowe wersje do 1.5.12 wymagają tego jednorazowego skopiowania kodu, aby otrzymać aktualizator. Powtórz instalację osobno na każdym profilu.

| Komenda | Działanie |
| --- | --- |
| `/paczki aktualizuj` | Sprawdza i pobiera nowsze opublikowane wydanie |
| `/paczki autoaktualizacja on` | Włącza automatyczne sprawdzanie i instalację w bezczynności |
| `/paczki autoaktualizacja off` | Wyłącza automatyczne aktualizacje |
| `/paczki aktualizacje status` | Pokazuje wersję i stan aktualizatora |

Automatyczne sprawdzanie jest domyślnie włączone: po uruchomieniu dodatku i co 6 godzin. Pobieranie może odbywać się podczas kursu. Podmiana kodu czeka na zatrzymanie wszystkich botów, zakończenie walki oraz własnych operacji kuriera. Aktualizator sam nie zatrzymuje kursu. Po instalacji bot pozostaje zatrzymany.

Aktualizator pobiera wyłącznie stabilne GitHub Releases z tego repozytorium. Sprawdza rozmiar, SHA-256, komplet plików i składnię Lua, przygotowuje cały nowy folder poza katalogiem wtyczek, zachowuje poprzedni kod i sprawdza powodzenie przeładowania. Przy wykrytym błędzie wraca do poprzedniej wersji. Suma SHA-256 sprawdza zgodność z manifestem wydania; nie jest osobnym podpisem autora.

Wymagane: Chimera **5.0.0-beta.13 lub 5.0.1**, Mudlet **4.20+** dla aktualizacji internetowych. Dostęp do GitHub Releases musi działać na komputerze gracza.

Aktualizacja z 1.5.13/1.5.14 do 1.5.15: pobierz ZIP i jednorazowo nadpisz cały folder dodatku, potem `/przeladuj`. Stary aktualizator może ignorować odpowiedzi po przekierowaniu GitHuba. Od 1.5.15 pobieranie odbywa się do osobnych plików i ten błąd jest naprawiony.

## Kolejność paczek (od 1.5.14)

1. Dostępne paczki **miejscowe** z bieżącej poczty. Po każdej dostawie bot wraca i ponownie odczytuje tablicę.
2. Gdy nie ma miejscowej paczki możliwej do doręczenia: **międzymiastowa poczta → poczta**. W nowej placówce ponownie pierwszeństwo mają miejscowe.
3. **Międzydomenowe** (również `miedzykrainowa`) są wyłączone z automatycznego wyboru.

W obrębie typu obowiązuje numer na tablicy. Cena, waga, odległość i ETA nie zmieniają kolejności. Waga musi mieścić się w ustawionym limicie. Oferty wyczerpane, odrzucone lub bez znanej drogi są pomijane z wyjaśnieniem w `/paczki oferty`. Przy dostępnej miejscowej nie liczymy tras dla międzymiastowych ani międzydomenowych. Dawne ustawienia `zarobek`, `zaplata`, `lekkie` nie przywracają starego rankingu.

## Zapisane dane

Instalacja wymienia kod dodatku. Zachowuje ustawienia profilu, bazę adresatów, zapisany kurs, statystyki i mapę. Repozytorium oraz wydania nie zawierają baz kont, danych logowania ani surowych logów graczy. Nie używaj `/paczki reset` do zwykłej aktualizacji.

Baza kuriera może być przenoszona i scalana między profilami. Najpierw zatrzymaj bota; na profilu źródłowym:

```text
/paczki baza eksport "C:/Temp/paczki_profil_A.json"
```

Na profilu docelowym:

```text
/paczki baza import "C:/Temp/paczki_profil_A.json"
/paczki baza
```

Import scala potwierdzonych adresatów i lokalizacje bez duplikowania wpisów. Nie scala całej natywnej bazy `/npc`, geometrii mapy ani własnych tekstowych tras `/paczki ucz`. Szczegóły: [PRZENOSZENIE_BAZY.txt](PRZENOSZENIE_BAZY.txt).

## Sterowanie

`/paczki` otwiera panel. `/bot paczki` rozpoczyna pracę, `/bot stop` zatrzymuje, `/paczki wznow` wznawia zapisany kurs. `/paczki tempo 1.5` ustawia opóźnienie kroków. `/paczki diagnostyka` pokazuje wersję, źródło lokalizacji NPC, planowanie tras i stan transportu.

Pełna instrukcja zachowanych funkcji: [README_PL.txt](README_PL.txt).

Automatyczne ponowne połączenie to osobny, opcjonalny dodatek **Chimera Reconnect Paczki**. Jego `/knet on` i `/knet off` nie sterują aktualizacjami kodu. Niniejsze wydanie go nie instaluje ani nie zmienia.

## Rozwój i wydawanie

`VERSION` i wersja modułu określają wydanie. Narzędzia `tools/test.py` oraz `tools/build.py` uruchamiają testy i budują ZIP, manifest `update.json` oraz komplet kodu `chimera-paczki-runtime.json`. Workflow wydania uruchamia testy przed przygotowaniem zasobów dla tagu `vX.Y.Z`; zmiana VERSION na main publikuje wydanie dopiero po przejściu testów. Ręczne uruchomienie lub sam tag przygotowuje szkic wydania.

Testy używają atrapy Mudleta oraz rzeczywistego kodu obu wskazanych wersji Chimery. Nie logują się na konta gry i nie stanowią testu na żywej postaci.

Wydanie ma stałą listę 25 plików wykonawczych. Zmiana formatu aktualizacji lub tej listy wymaga zaplanowania wersji przejściowej zgodnej ze starszym aktualizatorem.
