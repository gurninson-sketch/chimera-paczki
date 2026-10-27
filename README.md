# Chimera Paczki

Autonomiczny kurier dla **głównych skryptów Chimery** w Mudlecie. Wybiera najpierw paczki miejscowe, a po ich wyczerpaniu międzymiastowe poczta → poczta, dostarcza je do NPC i urzędów, obsługuje bramy oraz przeprawy, uczy się potwierdzonych adresatów i zachowuje kurs po rozłączeniu.

## Instalacja i aktualizacje

Pobierz [najnowsze wydanie](https://github.com/gurninson-sketch/chimera-paczki/releases/latest) i plik **Chimera_Paczki.zip**. Ten ZIP zawiera natywny dodatek Chimery; wypakuj go do katalogu profilu Mudleta.

1. W Mudlecie wpisz `/bot stop` i poczekaj na zakończenie trwającej operacji ruchu lub plecaka.
2. Zastąp cały folder `<profil>/chimera_wtyczki/chimera_paczki` folderem z ZIP-a (25 plików Lua).
3. Wpisz `/przeladuj` i zaczekaj na zakończenie ładowania.
4. Sprawdź `/paczki diagnostyka` — wersja 1.5.20. Rozpocznij `/bot paczki` albo kontynuuj zapisany kurs przez `/paczki wznow`.

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

## Start na poczcie po przeładowaniu

Po pełnym `/przeladuj` moduły GMCP mogą jeszcze nie mieć aktualnej pozycji, mimo widocznego opisu pokoju i załadowanej mapy. Przy starcie na rozpoznanej z opisu poczcie poza tekstowymi trasami Nuln bot odświeża dane GMCP, czeka na potwierdzoną postać i zgodną lokację na mapie, a następnie kontynuuje start. Dotyczy to też `/paczki poczta tutaj` przy brakującej lub niezgodnej pozycji. Sam opis poczty i stary cache Mudleta nie stanowią podstawy do wybrania paczki. STOP anuluje oczekiwanie.

`/paczki diagnostyka` pokazuje bieżącą nazwę i ID lokacji GMCP, pokój i ID mapy oraz ich zgodność. Jeśli świeżej lokacji brakuje na mapie profilu, bot zgłasza potrzebę wczytania mapy. Pobranie wspólnej bazy adresów nie wgrywa geometrii mapy.

## Kolejność paczek (od 1.5.14)

1. Dostępne paczki **miejscowe** z bieżącej poczty. Po każdej dostawie bot wraca i ponownie odczytuje tablicę.
2. Gdy nie ma miejscowej paczki możliwej do doręczenia: **międzymiastowa poczta → poczta**. W nowej placówce ponownie pierwszeństwo mają miejscowe.
3. **Międzydomenowe** (również `miedzykrainowa`) są wyłączone z automatycznego wyboru.

W obrębie typu obowiązuje numer na tablicy. Cena, waga, odległość i ETA nie zmieniają kolejności. Waga musi mieścić się w ustawionym limicie. Oferty wyczerpane, odrzucone lub bez znanej drogi są pomijane z wyjaśnieniem w `/paczki oferty`. Przy dostępnej miejscowej nie liczymy tras dla międzymiastowych ani międzydomenowych. Dawne ustawienia `zarobek`, `zaplata`, `lekkie` nie przywracają starego rankingu.

## Nieobecny adresat (od 1.5.16)

Po 5 minutach aktywnego szukania po mieście bot wraca do urzędu nadania, wyjmuje paczkę i wysyła `zwroc paczke`. Dopiero potwierdzenie gry pozwala wyczyścić kurs i wybrać kolejny. Pełny adresat w tej placówce jest pomijany przez 30 minut, również przy innej wadze lub nagrodzie oferty. Limit można zmienić przez `/paczki szukanie 5` (minuty 1–60). Zatrzymanie lub rozłączenie zachowuje zamiar zwrotu i wykorzystany czas szukania; nierozstrzygniętej operacji bot nie powtarza. Podczas patrolu pomija lokal jawnie zamknięty do rana.

## Bank w Nuln (zasady od 1.5.18)

Domyślny odstęp wynosi 120 minut. Po jego upływie bot odwiedza bank **wyłącznie przy okazji pobytu na poczcie w Nuln**, po rozliczeniu paczki. W innych miastach kontynuuje dostawy i zachowuje zaległy termin do następnego postoju w Nuln. Nie zmienia trasy ani miasta z powodu denominacji. Z poczty idzie `nw,nw` do banku, wyjmuje monety, wysyła `zdenominuj`, chowa je i wraca `se,se`. Każdy etap wymaga własnego potwierdzenia gry.

Odstęp liczy się od zakończonej wymiany; termin i etap są zapisywane osobno dla postaci. Przy aktualizacji z 1.5.17 dawne domyślne 30 minut zmienia się na 120 minut; zapisany termin jest jednorazowo wyznaczany od nowa. Inne ustawione odstępy pozostają zachowane. Ponowne ustawienie 30 minut w nowej wersji jest również zachowywane.

| Komenda | Działanie |
| --- | --- |
| `/paczki bank 120` | Ustawia odstęp w minutach, od 1 do 1440, i włącza wizyty |
| `/paczki bank teraz` | Zleca wizytę przy najbliższym postoju na poczcie Nuln; poza Nuln nie zmienia kursu, przy zatrzymanym bocie czeka na start |
| `/paczki bank status` | Pokazuje ustawienie, termin i etap wizyty |
| `/paczki bank off` / `/paczki bank on` | Wyłącza / włącza okresowe wizyty |

Przerwana wymiana nie jest powtarzana automatycznie. Jeśli bot zatrzymał się podczas operacji monet, dokończ denominację i schowaj monety ręcznie, potwierdź `/paczki bank rozliczone`, a potem użyj `/paczki wznow`. Wymagane są rozpoznane na mapie bank i poczta Nuln oraz pojemnik monet w `/pojemniki` lub automatycznie wykryty noszony plecak.

## Zmiana numeracji tablicy

Inny kurier może zabrać ostatnią paczkę po odczycie tablicy, zanim serwer wykona nasz wybór numeru. Bot porównuje rzeczywistego adresata z potwierdzenia odbioru z wybraną ofertą. Jeśli są inni, zwraca omyłkowo wydaną paczkę w potwierdzonym urzędzie nadania, bez wyznaczania nowej trasy. Własne potwierdzenie zwrotu pozwala ponownie odczytać tablicę. Taki zwrot nie blokuje adresata na 30 minut. Przerwanie i przeładowanie zachowuje zamiar zwrotu; brak odpowiedzi nie oznacza automatycznego powodzenia.

## Placówki bez nadań

Ebino pozostaje adresem doręczeń, ale nie jest wybierane do nadawania. Po rozliczeniu przesyłki bot najpierw sprawdza bezpieczną drogę w obie strony do poprzedniej poczty nadającej paczki i wraca tam. Dopiero jeśli tej możliwości nie ma, szuka innej placówki. Nie odczytuje tablicy ani nie wybiera nowej paczki w Ebino. Odpowiedź `Nie masz zadnej poczty.` na własny odczyt tablicy zapamiętuje brak nadań również po ponownym uruchomieniu. Pusta tablica z ofertami ma osobny, tymczasowy okres pomijania. `/paczki poczty stop` pozostawia bota w danej placówce.

Przy braku odpowiednich ofert podsumowanie pojawia się przed szukaniem innej poczty. Bot wybiera pierwszą dostępną placówkę z bezpieczną drogą w obie strony, bez kosztownego przeliczania wszystkich urzędów.

## Pozostałe banki na mapie

Poniżej dojścia od miejscowej poczty według danych mapy Chimery. Samą obsługę `zdenominuj` potwierdzono w logach tylko w Nuln. Bot automatycznie korzysta obecnie wyłącznie z banku Nuln.

| Miasto | Do banku od poczty | Powrót |
| --- | --- | --- |
| Bissingen | `n,w,nw,n,n,e` | `w,s,s,se,e,s` |
| Quenelles | `e,n,nw,n` | `s,se,s,w` |
| Varieno | `se,e,e,e,ne,ne,w` | `e,sw,sw,w,w,w,nw` |
| Ebino, placówka kurierska | `ne,se,sw,s,w` | `e,n,ne,nw,sw` |
| Karak Varn, czynna poczta | `e,nw,nw,w,n` | `s,e,se,se,w` |
| Crimmor | `wyjscie,s,bank` | `wyjscie,n,poczta` |

W Altdorfie mapa zawiera **Salę główną Banku Imperialnego**; nie potwierdzono punktu pocztowego, od którego można podać dojście. **Athel Loren jest dostępne wyłącznie dla leśnych elfów** i nie jest traktowane jako bank ogólnodostępny. Kantory są osobnymi lokacjami i nie oznaczają potwierdzonej możliwości denominacji.

## Bruno Rottel: patrol Kreutzhofen (od 1.5.22)

Bruno nie musi odpowiadać na przedstawienie się. Trzy potwierdzone doręczenia z logu 27.10.2026 wiążą jego paczkę z patrolującą grupą: **schludny orlonosy mężczyzna, podekscytowany orlonosy mężczyzna, hardy czarnooki mężczyzna i niebieskooki starszy mężczyzna**. Świeża obecność całej grupy w potwierdzonym obszarze Kreutzhofen pozwala spróbować oddania. Sukces nadal wymaga potwierdzenia gry i wypłaty. Skrypt nie zgaduje, który członek patrolu to Bruno, i nie tworzy fikcyjnego wpisu `/npc`.

Baza obejmuje doręczenia na dziedzińcu garnizonu i przy południowej stronie mostu; bot szuka wędrującego patrolu w mieście. Limit szukania, zwrot paczki i blokada ponownego wyboru przy dłuższej nieobecności pozostają aktywne. Trzy zweryfikowane pokoje po miejskiej stronie Soll uzupełniają brakujące metadane dojścia do garnizonu, bez rozszerzania obchodu na przeprawę przez rzekę i bez zmiany mapy profilu.

## Wspólna baza adresów (od 1.5.19)

Publiczny katalog [data/addresses.json](data/addresses.json) scala trzy zaakceptowane eksporty: Groro, Yarrim i Morrid. Początkowo obejmuje **63 adresatów i 69 lokalizacji**, bez konfliktów tożsamości. Źródła znajdują się w [data/address_sources](data/address_sources), a podsumowanie w [data/address_report.json](data/address_report.json). Są to potwierdzone adresy gry; wpis w katalogu nie potwierdza aktualnej obecności wędrującego NPC.

| Komenda | Działanie |
| --- | --- |
| `/paczki baza aktualizuj` | Pobiera wspólny katalog z GitHuba i scala go z lokalną bazą |
| `/paczki baza status` | Pokazuje stan pobierania i importu |
| `/paczki baza synchronizacja on` | Włącza automatyczne sprawdzanie |
| `/paczki baza synchronizacja off` | Wyłącza automatyczne sprawdzanie |

Automatyczne sprawdzanie jest domyślnie włączone: po 45 sekundach od załadowania dodatku i co 6 godzin. Pobieranie może odbywać się podczas pracy, ale import czeka na zatrzymanie botów i zakończenie operacji z paczką, ruchem oraz pojemnikami. Przed scaleniem powstaje kopia lokalnej bazy w `chimera_paczki_updates/addresses-backup-*.json`. Lokalne odkrycia są zachowywane, wielokrotny import nie duplikuje adresatów ani lokalizacji. Liczniki dostaw są scalane przez maksimum, bez sumowania już skopiowanych doręczeń. Pełna baza `/npc`, mapa i nagrywane trasy nie są częścią katalogu.

Nowe odkrycia dodajesz przez `/paczki baza eksport paczki_profil.json`, a następnie wgrywasz ten plik jako osobne źródło do `data/address_sources/`. Workflow **Consolidate addresses** waliduje wszystkie eksporty i aktualizuje wspólny katalog. Błędny eksport zatrzymuje scalanie; konflikt tożsamości NPC jest raportowany, bez arbitralnego wyboru postaci. Narzędzie można też uruchomić lokalnie: `python tools/consolidate_addresses.py`.

Bot pobiera dane z GitHuba; eksporty do repozytorium dodajesz samodzielnie. Kod nie zawiera tokenu GitHuba. Globalne wycofywanie błędnych wpisów z baz profili nie jest jeszcze obsługiwane.

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
