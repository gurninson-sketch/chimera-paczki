PACZKI 1.5.20 — BOT DO GŁÓWNYCH SKRYPTÓW CHIMERY
Zgodność: 5.0.0-beta.13 i 5.0.1; 27 października 2026

WYBÓR PACZEK OD 1.5.14

Najpierw miejscowe, następnie międzymiastowe poczta -> poczta.
Międzydomenowe/międzykrainowe wyłączone. W grupie numer tablicy;
waga tylko jako limit, cena i ETA informacyjne. Starsze opisy trybów
zarobek/zaplata/lekkie poniżej są historią i nie zmieniają tej reguły.
Aktualizacja z GitHuba: /bot stop, /paczki aktualizuj. Po zakończeniu:
/paczki diagnostyka i /paczki wznow. Nie resetuj bazy.

BANK W NULN — ZASADY OD 1.5.18

Domyślnie odstęp wynosi 120 minut. Bank tylko przy okazji pobytu
na poczcie w Nuln, po rozliczeniu paczki. W innych miastach bot
kontynuuje dostawy; zaległa wizyta czeka na postój w Nuln.
Bot nie zmienia miasta ani trasy dla denominacji:
potwierdzone wyjęcie monet -> zdenominuj -> własne potwierdzenie wymiany
-> potwierdzone schowanie -> powrót na pocztę Nuln i dalsze dostawy.
/paczki bank 120 ustawia minuty (1-1440), bank teraz zleca wizytę
przy najbliższym postoju na poczcie Nuln,
bank status pokazuje termin, bank off/on steruje wizytami okresowymi.
Termin i etap są zapisywane osobno dla postaci. Przerwanej wymiany bot
nie ponawia. Po ręcznej wymianie i schowaniu monet: /paczki bank rozliczone,
potem /paczki wznow. Wymagana mapa banku/poczty i pojemnik monet.
Ebino służy doręczeniom, bez nadawania paczek; po dostawie bot wybiera
inną pocztę. Potwierdzony brak tablicy jest zapamiętywany między sesjami.

ZMIANA NUMERACJI I EBINO OD 1.5.18

Jeśli inny kurier zmieni numerację i gra wyda paczkę dla innego adresata,
bot nie jedzie do niego: zwraca przesyłkę w potwierdzonym urzędzie nadania,
czeka na własny ACK i ponownie czyta tablicę. Bez blokady adresata.
Zwrot pozostaje zapisany po STOP/przeładowaniu, bez rozwiązywania celu.
Po doręczeniu w Ebino bot nie próbuje nadawać. Sprawdza bezpieczny powrót
do poprzedniej nadającej poczty; przy braku tej drogi szuka innej placówki.
Athel Loren nie jest bankiem ogólnodostępnym: wejście tylko dla leśnych elfów.
Automatyczne wizyty bankowe w tej wersji nadal dotyczą wyłącznie Nuln.

INSTALACJA I AKTUALIZACJA

Zatrzymaj bota na lądzie. Rozpoczęty kurs pozostanie zapisany.
1. /bot stop
2. Rozpakuj archiwum do katalogu profilu Mudleta. Nadpisz cały folder:
     <katalog profilu>/chimera_wtyczki/chimera_paczki/
   Pliki: init.lua, core.lua, routes.lua, new_routes.lua, npc.lua,
   travel.lua, offices.lua, scope.lua, road.lua, ferry.lua, journey.lua,
   transport_data.lua, inventory.lua, memory.lua, path.lua, postal.lua,
   checkpoint.lua, escape.lua, recovery.lua, eta.lua, karak_transport.lua, city.lua, city_data.lua, planner.lua, updater.lua.
   Łącznie 25 plików Lua.
   Katalog profilu: echo(getMudletHomeDir()).
3. Wykonaj pełne /przeladuj, aby wczytać wszystkie moduły nowej wersji.
4. /wtyczki pokaże chimera_paczki; /bot pokaże [paczki]. Panel: /paczki.
5. Bez paczki, na rozpoznanej poczcie: /paczki start 1
   Po jednej dostawie do NPC bot wróci do nadawcy. Po dostawie do innego
   urzędu zakończy próbę na poczcie docelowej. Pętla: /bot paczki.

Ten sam folder działa w różnych profilach. Kod nie zawiera konta, hasła
ani imienia postaci. Mapę i własne wpisy /npc zapewnia aktualny profil.
Po wczytaniu bot jest wyłączony; może pokazywać odzyskany, wstrzymany kurs.
Nie instaluje ani nie zmienia mapy.

WZNOWIENIE PO ROZŁĄCZENIU, PRZEŁADOWANIU LUB RESTARCIE

Wersja 1.5.0 zapisuje kurs osobno dla każdej postaci w aktualnym profilu.
Zachowuje urząd nadania, adresata i potwierdzony stan paczki, statystyki,
limit dostaw, cel przejścia między pocztami oraz potwierdzony pojemnik
paczki. Nie zapisuje haseł, treści logowania, dawnych komend marszu ani
numerów pokoi Mudleta. Dla tras mapowych pozostałą drogę wylicza ponownie
z aktualnej mapy i pozycji GMCP. Znane trasy tekstowe Nuln korzystają
z własnego drzewa przejść i ponownego rozpoznania opisu lokacji.

Tożsamość ustala z kanonicznej nazwy postaci w Char.Info. Odmienione imię
w powitaniu przy logowaniu nie oznacza zmiany postaci i nie zeruje kursu.
Inna postać ma osobny zapis; powrót do poprzedniej pozwala odzyskać jej kurs.
Przy odtwarzaniu zapisu bez potwierdzonej tożsamości pozostaje wstrzymany.

Po ponownym połączeniu lub wczytaniu profilu:
1. /paczki wznow lub /bot paczki — zgłoś kontynuację zapisanego kursu.
2. Jeśli brakuje GMCP, bot odświeży subskrypcję i poczeka na dane serwera.
3. Po ich otrzymaniu wznowi automatycznie. Panel /paczki pokazuje stan;
   /paczki stop albo /bot stop anuluje oczekujące uruchomienie.

Sam odczyt zapisu nie uruchamia bota. Wznowienie nie odtwarza przebytej
drogi i nie powtarza niepotwierdzonego kroku. Nierozstrzygnięty odbiór,
oddanie, wypłata lub przeniesienie monet zatrzymuje wznowienie do czasu
sprawdzenia rzeczywistego stanu gry. Wznowienie trasy mapowej wymaga świeżej
pozycji GMCP; sam tytuł pokoju jej nie zastępuje. Trasa tekstowa Nuln nadal
wymaga poprawnego dopasowania do znanych opisów i wyjść.

Aktualizacja nie odzyska wstecz kursu, który wersja 1.4.2 już wyzerowała.
Jeśli faktycznie niesiesz taką paczkę, sprawdź ją i pojemnik, wyjmij ją do
rąk, a następnie wskaż pełnego adresata, np.:

  /paczki paczka Urzad pocztowy miasta Urbimo
  /paczki wznow

To polecenie opisuje rzeczywiście posiadaną paczkę. /paczki reset usuwa
zapis bieżącej postaci i jej statystyki, ale nie usuwa przedmiotu w grze.

OFERTY, NAZWY FILII I POWODY POMIJANIA PACZEK

Wspólny rejestr 25 poczt rozpoznaje pełne warianty nazw, m.in. „Urzad
pocztowy w Nuln”, „Poczta wolnego miasta Nuln”, „Urzad pocztowy w Urbimo”,
„Poczta miasteczka Varieno”, Crimmor, Karak Varn/Karak-Varn oraz widoczne
w grze Kreutzhoffen. Dotyczą znanych, zweryfikowanych lokalizacji.
Samo podobieństwo nazwy ani ogólne „Poczta” nie wskazuje dowolnego celu.
Znana poczta ma pierwszeństwo przed sprzecznym wpisem pamięci kuriera.

  /paczki oferty       Ostatnia ocena każdej pozycji pełnej tablicy.

Podgląd zawiera źródło, limit wagi, strategię oraz przyczynę pominięcia
albo pozycję w rankingu i koszt drogi. Jest też przycisk w panelu /paczki.
Ocena jest migawką: późniejsza zmiana tablicy lub ustawień nie oznacza,
że stara oferta nadal istnieje. Przy braku odpowiednich ofert bot wypisuje
liczbę odrzuceń z powodu wagi, adresata/trasy i innych warunków także
przed automatyczną zmianą poczty.

Limit pozostaje ustawieniem gracza: np. paczka 8 kg nie spełnia limitu
6,2 kg. Rozpoznanie nazwy nie gwarantuje kompletnej obsługiwanej drogi.
Przy trybie zarobek dostępna paczka do innej poczty może zajmować dalszą
pozycję niż krótki kurs miejscowy; sam fakt jej obecności nie gwarantuje
natychmiastowego wybrania.

PO PEŁNYM PRZEŁADOWANIU NA POCZCIE

Zapis kursu nie zastępuje świeżych danych serwera.
Pełne /przeladuj tworzy od nowa stan API GMCP. Jeśli brakuje danych,
/paczki wznow albo /bot paczki odnawia subskrypcję Char i Room i czeka
na rzeczywiste dane serwera. Po otrzymaniu tożsamości i pozycji uruchamia
kuriera automatycznie, bez ponownego wpisywania wznowienia. W tym czasie
nie wykonuje ruchu ani komend paczki. Podejmuje najwyżej trzy próby
odświeżenia w ciągu 60 sekund; brak odpowiedzi pozostawia kurs zapisany.
STOP, ręczna komenda do gry, ruch, walka, niskie HP, rozłączenie, reload
lub uruchomienie innego bota anulują oczekujące uruchomienie.
Nie odtwarza zdarzeń z surowej pamięci gmcp ani nie zgaduje imienia.

CAMPOGROTTA I SKRÓTY WYMAGAJĄCE WSPINACZKI

Planer pomija „wespnij ...” i „wspinaj ...”, które wymagają umiejętności
i odpowiednich warunków. Gdy najtańsza trasa mapy zawiera takie przejście,
wyszukuje kompletny objazd w aktualnej mapie profilu. Zwykłe kierunki u/d,
nazwane wyjścia i trakty przełęczy pozostają dostępne. Górskie skróty
w Górach Szarych i dzikie lokacje Las Loren są wyłączone. Wybrany objazd zachowuje
wagi terenu, wagi wyjść oraz blokady pokoi i przejść ustawione na mapie.
Nie zmienia globalnej mapy ani jej blokad. Przy rozpoczęciu objazdu podaje
komunikat „Omijam nieobslugiwany skrot”.

Koszt objazdu jest uwzględniany przed wyborem paczki i przy zmianie poczty.
Jeśli nie ma kompletnego obsługiwanego połączenia, bot nie wybiera oferty.
Jawna odmowa przejścia z powodu umiejętności kończy próbę od razu, bez
czekania na timeout i bez ponawiania niewykonanego ruchu.

Tablica Campogrotty z nagłówkiem „Agente Postalle di Tilea” jest również
rozpoznawana. Nadal wymagana jest pełna tablica z końcowym komunikatem;
sam nagłówek lub urwany wiersz nie uruchamia odbioru.

ODZYSKANIE NIESIONEJ PACZKI POCZTOWEJ PO AKTUALIZACJI

Jeżeli nie ma poprawnego zapisu kursu, np. starsza wersja utraciła już
paczkę z pamięci podczas drogi do Campogrotty:
1. /bot stop
2. Nadpisz cały folder dodatku i wykonaj pełne /przeladuj.
3. Ustal, że faktycznie nadal masz tę paczkę; jeśli była schowana, wyjmij
   ją do rąk. Można użyć /wep dla pojemnika przypisanego w Chimerze.
4. /paczki paczka Poczta w Campogrotta
5. /paczki wznow

Ręczne wskazanie adresata nie wysyła ruchu ani nie dopisuje niepotwierdzonego
adresata do bazy nauki. Dla paczki do innej poczty może odtworzyć pozostałą
drogę od aktualnego, rozpoznanego miejsca. Dostawy do NPC nadal wymagają
znanego urzędu nadania, żeby zachować poprawny cel powrotu.

AUTOMATYCZNE UCZENIE ADRESATÓW

Domyślnie włączone. Po faktycznym odbiorze paczki, oddaniu i wypłacie bot
zapisuje pełnego adresata oraz dokładny hash lokacji z chwili oddania.
Jeśli GMCP jednoznacznie potwierdzi tożsamość znanego NPC, zapisuje też
jego identyfikator, imię i opis. Sam opis istoty, dojście do celu albo
ręczne /paczki paczka <adresat> bez potwierdzonego odbioru nie tworzą wpisu.

Po kolejnej dostawie aktualizuje licznik oraz kolejność potwierdzonych
miejsc. Przy nowych ofertach korzysta z tej pamięci przed rozstrzyganiem
podobnych imion w /npc. Droga jest obliczana z aktualnej mapy po hashach,
a nie zapamiętanych numerach pokoi. Nadal wymaga dostępnej drogi i powrotu
do urzędu. Przy samej potwierdzonej lokalizacji dochodzi do tego miejsca,
przedstawia się i podejmuje jedną próbę oddania sprawdzaną przez grę.

Pierwsze doręczenie do adresata całkowicie nieznanego botowi można wykonać
ręcznie: wybierz paczkę, przejdź do właściwego miejsca i oddaj ją. Bot musi
być załadowany, żeby zobaczyć odpowiedzi gry, a miejsce musi być poprawnie
rozpoznane na mapie. Po oddaniu ORAZ wypłacie zapisze adresata. Następną
taką paczkę może już wybrać i dostarczyć automatycznie, jeżeli spełnia
dotychczasowe warunki oferty i mapy. Nie wybiera w ciemno nieznanej paczki
ani nie odkrywa sam nieistniejących połączeń mapy czy nowych statków.

  /paczki baza                     Podgląd zapamiętanych adresatów.
  /paczki baza usun Imie Nazwisko   Usuń dokładnie wskazanego adresata.
  /paczki nauka auto               Włącz zapisywanie udanych doręczeń.
  /paczki nauka stop               Wyłącz nowe zapisy; zachowaj odczyt bazy.

Licznik adresatów i przełącznik nauki są też w panelu /paczki. Pamięć jest
trwała w aktualnym profilu Mudleta: przetrwa /przeladuj oraz restart.
Postacie w tym samym profilu korzystają z tej samej bazy; osobne profile
mają osobne bazy. Ta wspólna baza adresatów jest oddzielna od zapisów
bieżących kursów, które są osobne dla każdej postaci. /paczki reset czyści
kurs i statystyki bieżącej postaci wraz z jej checkpointem, zachowując
wyuczonych adresatów. Dodatek nie zmienia wspólnej bazy NPC Chimery.

ODPOCZYNEK I AUTOMATYCZNE WZNOWIENIE

Zmęczenie uruchamia odpoczynek, zachowując paczkę, cel, urząd, limit
i statystyki. Bot zachowuje sterowanie w Botach i pyta o „stan” co 10 sekund.
Wznawia po NOWYM Char.Vitals ze zmęczeniem <= „Rusza przy” w ustawieniach
Chodzik (domyślnie 20%). Odpoczywa od niższego progu zmęczenia Chodzika
i Automatyzacji (domyślnie 80%), także przy starcie lub odmowie kroku.

Odpowiedź na już wysłany krok musi być potwierdzona przed wznowieniem;
bot nie powtarza niepotwierdzonego ruchu. Czeka maksymalnie 15 sekund.
Na promie podczas odpoczynku obserwuje również następne cykle rejsu.
STOP, ręczne komendy, numpad, teleport, zmiana postaci, rozłączenie
i reload anulują automatyczne wznowienie; zapisany kurs pozostaje
do ręcznego /paczki wznow. Niskie HP uruchamia regenerację; rozpoznany
atak NPC nie przerywa marszu (szczegóły poniżej). Nierozstrzygnięty
odbiór/oddanie paczki wymaga sprawdzenia rzeczywistego stanu gry.

PACZKA I MONETY W PLECAKU

Bot najpierw używa pojemników przypisanych w głównej Chimerze. Dla plecaka
można ustawić:

  /pojemniki inne plecak
  /pojemniki monety plecak

Możesz wskazać własny pojemnik obsługiwany przez /pojemniki. „Inne” to
pojemnik na paczkę, „Monety” na wypłatę. Ustawienia są osobne w profilach.

Bez przypisanego pojemnika działa domyślne automatyczne wykrywanie:
bot wysyła własne „i” i przez maksymalnie 1,5 sekundy rozpoznaje jeden
noszony plecak z odpowiedzi „Nosisz na plecach ... plecak.”. Nie wybiera
plecaka z ziemi ani komunikatu o innej osobie. Potwierdzony pojemnik paczki
zapamiętuje do jej wyjęcia, także po zmianie przypisań /pojemniki.
Przed schowaniem monet ponownie sprawdza noszony plecak. Wykrywanie nie
zmienia globalnych przypisań Chimery. Bez jednego rozpoznanego plecaka
podaje przyczynę i kontynuuje niesienie przy sobie, bez zgadywania celu.

  /paczki plecak auto    Włącz wykrywanie — domyślnie włączone.
  /paczki plecak stop    Wyłącz wykrywanie; zachowaj przypisania /pojemniki.

Panel pokazuje stan wykrywania, globalne przypisania i ostatnio wykryty
plecak. Jawne przypisanie zawsze ma pierwszeństwo i nie wymaga zapytania i.
STOP, odpoczynek, rozłączenie i przeładowanie anulują niezakończone
wykrywanie. Spóźniony opis ekwipunku nie uruchamia wkładania po STOP.

Po potwierdzonym odbiorze chowa paczkę, przed oddaniem wyjmuje ją, a po
wypłacie chowa monety. W komendach gry używa „paczke”, a nie długiego
opisu „pocztowa paczke”. Każde przeniesienie wymaga własnego potwierdzenia
gry przed dalszą drogą. Limit wagi pozostaje ustawiony przez gracza.

Przy /pojemniki otwieraj tak kolejność jest następująca: otwórz pojemnik
→ poczekaj na potwierdzenie otwarcia → przenieś paczkę lub monety → poczekaj
na potwierdzenie przeniesienia → zamknij pojemnik. Nie wysyła przeniesienia
przed potwierdzeniem otwarcia ani nie uznaje cudzej czynności za własną.
Tak samo przygotowuje pojemnik przed wyjęciem paczki do oddania.

Przy /pojemniki otwieraj nie nie otwiera ani nie zamyka go automatycznie.
Pojemnik musi być dostępny do przeniesienia; odmowa lub nieznany wynik
nie uruchamiają w ciemno dalszych operacji.

Brak potwierdzenia zatrzymuje bot bez zgadywania położenia paczki.
Spóźnione potwierdzenie może uaktualnić jej położenie, ale nie wysyła
komend po STOP. Przy nieznanym stanie sprawdź plecak, weź paczkę do rąk
i wpisz /paczki paczka <adresat>, a potem /paczki wznow.

TEMPO MARSZU

Domyślnie bot dziedziczy „Opóźnienie” z ustawień Chodzik Chimery.
Wcześniej zapisane własne tempo inne niż domyślne 0,35 s jest zachowane.

  /paczki tempo 1,5         Własne opóźnienie 1,5 s; kropka też działa.
  /paczki opoznienie 2      Alias: 2 sekundy przerwy.
  /paczki tempo             Podgląd wartości i źródła ustawienia.
  /paczki tempo chodzik     Powrót do ustawień głównego chodzika.

Panel /paczki pokazuje aktualne sekundy i źródło oraz [wolniej],
[szybciej], [z chodzika]. Własny zakres 0,15–60 sekund. Większa liczba
oznacza wolniejszy marsz. Przerwa następuje po potwierdzeniu lokacji.
Zmiana tempa w trakcie przerwy rozpoczyna ją od nowa; już wysłany krok
kończy się normalnie. Ustawienie zapisuje się w profilu.

BRAMY I TRAKTY

Bot sam wykonuje pojedyncze kroki mapy i czeka na potwierdzenie pokoju
przez mapper oraz GMCP. Własne komendy nie są już odgadywane po aktualnej
liście wyjść, więc chwilowy brak kierunku za zamkniętą bramą nie jest
uznawany za ręczne przejęcie sterowania.

Na znanej bramie wysyła właściwe „uderz w brame” albo „uderz we wrota”.
Kontynuuje po „brama zostaje otwarta”, „wrota zostaja otwarte” albo
„Alez brama jest przeciez otwarta!”. Samo „Uderzasz w brame” lub
„Czekac tam!” nie wystarcza. Nie wysyła kierunku po stałych 0,1 sekundy.
Powtarza otwieranie tylko w ograniczonym zakresie i na podstawie odmowy
lub ponownego zamknięcia, bez powtarzania niepotwierdzonego ruchu.

Zwykłe dostępne przejście na ulicy oznaczonej jako brama nie wymaga
otwierania. Zamknięte wrota Quenelles są obsługiwane także wtedy, gdy
GMCP nadal pokazuje prowadzące przez nie wyjście. Nazwane wyjście może
zastąpić kierunek mapy, jeżeli prowadzi do dokładnie tego samego pokoju.

Cisza po ruchu kończy próbę po 15 sekundach. Bot nie ponawia takiego
kroku w ciemno: spóźniona odpowiedź mogłaby oznaczać podwójne przejście.
Zła krawędź mapy lub utrata łączności nadal wymaga ustalenia pozycji.

QUENELLES — PROM W OBIE STRONY

Dla relacji Nuln ↔ Quenelles używana jest potwierdzona przeprawa przez
Grismerie. Drogi do obu brzegów i od nich są obliczane z mapy profilu;
nie są odtwarzaniem nieudanych lub powtórzonych kierunków z logu.
Bot nie wybiera zastępczo nieprzetestowanego objazdu przez Loren/Orcal.
Oba brzegi oraz drogi do nich muszą istnieć na mapie przed odbiorem paczki.

Etapy: dojście do brzegu → oczekiwanie na prom → wejście → potwierdzenie
odpłynięcia → potwierdzenie przybicia → jedno „zejdz na brzeg” → kontrola
właściwego brzegu i pokoju mapy → dalsza droga do poczty.
Na tym promie bot nie kupuje biletu: w logu „kup bilet” dawało „Hmm?”.
Obsługiwany jest wyłącznie ten potwierdzony prom, nie dowolny statek.

/bot stop anuluje także oczekiwanie i zaplanowane zejście. /paczki wznow
może kontynuować rejs w tej samej sesji, wyłącznie gdy GMCP potwierdza
zapamiętany pokład. Zapis kursu zachowuje paczkę, ale po przeładowaniu
profilu nie odtwarza fazy rejsu. Dalsza droga wymaga ustalenia bezpiecznej
pozycji i właściwego brzegu.
Powtórzona linia przybicia nie wysyła kolejnej komendy zejścia.

PRACA MIĘDZY URZĘDAMI

Dostawa do NPC: powrót do poczty nadania i następna tablica.
Dostawa do poczty w innym mieście: po potwierdzonym oddaniu I wypłacie
bot przyjmuje tę placówkę jako nowy urząd pracy i czyta jej tablicę.
Nie wraca do poprzedniej poczty tylko dlatego, że tam odebrał paczkę.
Ustawiony limit dostaw jest zachowany przy zmianie miasta i wznowieniu
zapisanego kursu.

Domyślnie działa automatyczna zmiana poczty. Jeśli pełna tablica nie
zawiera odpowiedniej znanej oferty w limicie wagi, bot bez paczki wybiera
najbliższy osiągalny urząd z katalogu 24 placówek. Wymagana jest kompletna
obsługiwana droga w obie strony. Pusty urząd pomija przez 10 minut, aby
nie krążyć między placówkami. Bez innego celu pozostaje i odświeża tablicę.

  /paczki poczty               Podgląd najbliższych poczt i kosztów.
  /paczki poczty auto          Włącz automatyczne szukanie innej poczty.
  /paczki poczty stop          Wyłącz automat, anuluj jego zapamiętany cel.
  /paczki poczta Nuln          Ręcznie wybierz placówkę i przejdź do niej.
  /paczki poczta Bogenhafen    Inny przykład ręcznego celu.
  /paczki poczta tutaj         Pracuj na poczcie, na której obecnie stoisz.

Ręczny wybór ignoruje cooldown pustych poczt i zastępuje stary cel.
Zachowuje licznik dostaw oraz zarobek. Wymaga jednoznacznej nazwy miasta
lub pełnej nazwy urzędu i odpowiedniej mapy. Samo „Poczta” jest niejednoznaczne.
Z niesioną lub nierozliczoną paczką zmiana urzędu jest blokowana.
Wybór ręczny może uruchomić bota albo przekierować już działającego kuriera.

/paczki poczty stop anuluje trwające przejście AUTOMATYCZNE. Nie anuluje
ręcznie wybranego celu — do zatrzymania każdego ruchu służy /bot stop.
Świeże /bot paczki, bez paczki i na rozpoznanej poczcie, zaczyna pracę
w bieżącym urzędzie, zamiast wznawiać stary plan Jaskare lub innego miasta.
/paczki wznow zachowuje znaczenie: kontynuuj zapamiętany kurs.

POZOSTAŁE KOMENDY

/paczki                     Panel sterowania, źródła, celu i zarobku.
/bot paczki                 Ciągła praca.
/bot stop                   Zatrzymaj aktywnego bota.
/paczki start 10             Dziesięć kolejnych dostaw.
/paczki wznow                Wznów zapamiętaną paczkę albo przerwane przejście.
/paczki status               Stan i potwierdzone wypłaty.
/paczki npc Johan Kornwalz   Sprawdź adresata, mapę i koszt drogi.
/paczki trasy                Wbudowane i nauczone trasy tekstowe z Nuln.
/paczki limit 6.7            Maksymalna waga paczki; domyślnie 3,2 kg.
/paczki tryb zarobek         Wartość nagrody względem kosztu drogi.
/paczki tryb zaplata         Najwyższa pełna nagroda.
/paczki tryb lekkie          Najlżejsza osiągalna paczka.
/paczki tempo 0.6            Odstęp po potwierdzonym kroku kuriera.
/paczki odswiezanie 60       Odczyt tablicy co 60 s przy braku pracy.
/paczki paczka Olaf Hubner   Ustaw adresata paczki faktycznie trzymanej w rękach.
/paczki reset                Usuń zapis kursu tej postaci i statystyki; zachowaj bazę.
/paczki ucz Imie Nazwisko    Nauka odwracalnej trasy tekstowej z Nuln.

WYBÓR I ROZLICZENIE PACZEK

Bot czyta całą tablicę, uwzględnia zawinięte wiersze oraz bieżące numery.
Sprawdza faktycznego adresata po odbiorze. Nieznany zwrot lub brak
potwierdzenia odbioru/oddania powoduje pauzę, bez założenia sukcesu.
Odpowiedź na „zwroc paczke” nadal wymaga potwierdzenia na żywym serwerze.

Ręczne „wybierz paczke <numer>” podczas pauzy jest obserwowane; po odpowiedzi
gry bot zapamiętuje faktyczną paczkę i rzeczywisty urząd nadania. Ręczne
„oddaj paczke” również aktualizuje stan po potwierdzeniu i wypłacie. Bot
pozostaje wstrzymany do następnej komendy sterowania. Nie myli ręcznie
odebranej paczki z pustymi rękami przy nowym starcie.

Ranking uwzględnia wszystkie nominały: 1 zł = 20 sr = 240 md, 1 sr = 12 md.
Dla NPC koszt obejmuje dojście i powrót; dla doręczenia do poczty koszt
obejmuje drogę do niej, ponieważ bot kontynuuje tam pracę. Wagi mapy i
szacunkowy koszt przeprawy są wskaźnikiem wyboru, nie gwarancją stawki
za godzinę. Zarobek jest liczony wyłącznie z rzeczywistych wypłat.

BAZA NPC I TRASY

/npc pozostaje zwykłą komendą głównych skryptów. Bot korzysta z jej API:
pełnej nazwy, tytułu i jednoznacznego imienia, bez losowania spośród kilku
kandydatów. Na właściwej lokacji może przedstawić się NPC-owi widocznemu
pod opisem, odświeżyć GMCP i podjąć jedną próbę oddania sprawdzaną przez grę.
Sam opis spotkany po drodze nie potwierdza tożsamości.

Dziesięć tras tekstowych z Nuln: Henry Schmidt, Ludwig Gołębiarz, Olaff
Meier Młodszy, Fryderik Miecznik, Joachim Eisenberg, Berta Leibentropp,
Rudolf Karczmarz, Reinhard Fleischer, Olaf Hubner, Rolph Ederson.
Pozostałe cele korzystają z bazy /npc i mapy. Nowe profile nie otrzymują
osobistej mapy ani bazy NPC przez samo zainstalowanie tego folderu.
Nauka tekstowa wymaga odbioru, doręczenia i powrotu dokładnie odwróconymi
kierunkami; nie obsługuje promu ani specjalnych przejść.

ANNIBALE — OCZEKIWANIE NA OKRESOWO NIEOBECNEGO ADRESATA

Specjalne oczekiwanie dotyczy wyłącznie pełnego adresata
„Annibale Malacresta Lettore”. Po dojściu do jego znanej, osiągalnej lokacji
z bazy /npc bieżącego profilu bot pozostaje w tym miejscu, gdy adresata
nie ma. Nie wchodzi na statek i nie podąża za nim do następnych pokoi.
Nie dodaje portu do osobistej bazy NPC na podstawie samej nazwy Annibale.
Jeśli baza zna kilka lokalizacji, nadal są one danymi bieżącego profilu;
oczekiwanie nie rozszerza tej listy o wymyślone miejsca ani pokład.

Co 10 sekund odświeża opis i sprawdza aktualne dane NPC/GMCP. Świeże,
jednoznaczne potwierdzenie właściwego Annibale w tej samej lokacji, także
nazwany komunikat jego przybycia, pozwala kontynuować oddanie paczki.
Sam dawny wpis obecności, anonimowy opis albo upływ czasu nie wystarczają.
Bot nie zakłada rozkładu rejsów ani maksymalnego czasu do jego powrotu.

Jeżeli adresat odejdzie przed rozliczeniem, po próbie oddania tylko jawna
odmowa gry o nieobecnym adresacie pozwala wrócić do tego oczekiwania.
Komunikat o braku paczki, brak potwierdzenia oddania lub wypłaty i timeout
nie są traktowane jak zwykła nieobecność. Wtedy pozostaje pauza wymagająca
sprawdzenia stanu gry; nie dopisuje dostawy ani nie ponawia jej w ciemno.

Oczekiwanie jest częścią aktywnego kursu i podlega /bot stop. Ręczne komendy,
numpad, teleport, rozłączenie, zmiana postaci i reload anulują jego
zapytania. Atak NPC przełącza na dalszy marsz, a niskie HP na
automatyczną regenerację. Zmęczenie przełącza na dotychczasowy odpoczynek;
podczas niego nie trwa osobne odpytywanie obecności. Po wznowieniu obecność
jest sprawdzana ponownie. Trwałe kursy i pozostałe zasady z 1.5.0 pozostają
zachowane. Inni nieobecni adresaci nadal używają dotychczasowych reguł.

ZATRZYMANIE I PAMIĘĆ

Ręczne komendy do gry (np. i, wez monety), numpad, apokalipsa
i rozłączenie wstrzymują bota. Rozpoznany atak NPC nie zatrzymuje
bieżącej trasy; niskie HP poza przejściem przez walkę uruchamia regenerację. Zmęczenie włącza opisany wyżej
automatyczny odpoczynek. Komendy własne
kuriera przechodzą przez jego nadajnik i nie są uznawane za ręczne.
Wysłany już krok może jeszcze otrzymać odpowiedź po zatrzymaniu.

Konfiguracja, nauczone trasy i baza adresatów są zapisywane w profilu.
Checkpoint bieżącego kursu jest osobny dla każdej kanonicznej postaci.
Rozłączenie i przeładowanie zatrzymują sterowanie, zachowując ten zapis.
Zmiana postaci nie usuwa kursu poprzedniej. Po ponownym wczytaniu zawsze
sprawdź rzeczywisty stan gry przed ręcznym /paczki wznow.

WERYFIKACJA

Scenariusze offline i ich wyniki wymieniono w TEST_REPORT.txt.
Obejmują rzeczywiste moduły loadera,
Context, Bus, GMCP, mappera i Botów z beta.13, atrapę Mudleta, syntetyczne
mapy oraz dokładne odpowiedzi z logów. Są pełne testy promu w obie strony,
opóźnionej bramy z nieaktualnymi wyjściami, wznowienia na zmapowanym
pokładzie, pracy na poczcie docelowej, wyboru ręcznego i przeładowania.
Nowe testy obejmują odpoczynek, spóźniony ruch, pracę z pojemnikami,
zmiany tempa w trakcie marszu i zapis ustawień przez przeładowanie.
Wersja 1.4 dodaje testy pamięci, pełnej sekwencji odbiór/oddanie/wypłata,
ponownego użycia nowego adresata po przeładowaniu i zmiany numerów mapy.
Wersja 1.4.1 dodaje testy ważonego objazdu z pominięciem wspinaczki,
blokad mapy, zwykłego u/d, tablicy Tilei i odzyskania paczki na drodze.
Wersja 1.4.2 dodaje testy wspólnego rejestru adresów, diagnozy ofert oraz
wykrywania plecaka i pełnego cyklu chowania bez konfiguracji pojemników.
Wersja 1.5.0 dodaje CHECKPOINT_REPORT.txt i RESUME_NATIVE_REPORT.txt:
zapis osobno dla postaci, różne formy imienia przy logowaniu, wznowienie
po rozłączeniu i reloadzie, zmianę numerów mapy, pojemnik oraz blokadę
niejednoznacznych wyników operacji. ANALIZA_DISCONNECT_152832.txt zawiera
filtrowane dowody problemu utraty kursu po rozłączeniu.
Wersja 1.5.1 dodaje test_periodic_npc_native.lua oraz
PERIODIC_NPC_NATIVE_REPORT.txt: oczekiwanie w stałej lokacji, świeżą
obecność adresata, odjazd przed oddaniem oraz anulowanie oczekiwania.
Testy pojemników obejmują też kolejność otwarcie → potwierdzenie →
przeniesienie → zamknięcie, komendy „paczke” i ustawienie otwieraj nie.
ANALIZA_ANNIBALE.txt oddziela fakty z tablic i katalogu transportu od
zgłoszonego zachowania NPC; dane źródłowe są w annibale_analysis.json.
Nie przeprowadzono próby w działającym oknie Mudleta ani na serwerze.
Raporty oraz dane dowodowe znajdują się w dokumentacja/.

Źródła: https://gitlab.com/bfbps-group/chimera-mud-skrypty
Tag 5.0.0-beta.13, commit4376ef2f9eeef8d95e7ba8070a22d0428100ed19.
Główne pliki Chimery i Kozobota nie są modyfikowane.

POPRAWKA 1.5.2: już otwarty plecak
Odpowiedź „Skorzany plecak juz jest otwarty.” jest potwierdzeniem otwarcia.
Bot przechodzi do przeniesienia paczki lub monet, a następnie czeka na
potwierdzenie przeniesienia i zamknięcia. Obsługiwane są oba szyki
„juz jest otwarty” i „jest juz otwarty” oraz formy żeńskie pojemników.
Cudze czynności, wypowiedzi i przeczenia nie potwierdzają otwarcia.

POPRAWKA 1.5.3: wznowienie po pełnym przeładowaniu
/bot paczki kontynuuje istniejący kurs; /paczki start zachowuje kontrolę
nowej pracy. Żądanie wznowienia z niepełnym GMCP pozostaje oczekujące
przez maksymalnie 60 sekund i kontynuuje automatycznie po świeżych danych.
Samo przeładowanie bez żądania startu nadal nie uruchamia kuriera.
Serwer musi odpowiedzieć na subskrypcję; brak odpowiedzi nie jest sukcesem.
Po rozliczonej dostawie do innej poczty bot może kontynuować w aktualnej
rozpoznanej placówce, także po ręcznym przejściu do innego miasta.
Dokładny zapisany cel pozwala rozpoznać placówkę Ebino bez zgadywania
mapy. Odpowiedź „Nie masz zadnej poczty.” na własny odczyt tablicy jest
obsługiwana jak brak ofert: zmiana urzędu lub odświeżenie według ustawień.

PRZENOSZENIE NA INNE PROFILE — 1.5.4
Ten sam folder dodatku instaluje się na każdym profilu z głównymi skryptami
Chimery i mapą. Każdy profil zachowuje własne ustawienia, kurs i zarobki.
Nauczoną bazę NPC i poczt przenosi osobny plik JSON; szczegółowa procedura
znajduje się w PRZENOSZENIE_BAZY.txt. Komendy:
  /paczki baza eksport [plik]
  /paczki baza import [plik]
Domyślny plik to chimera_paczki_baza.json w katalogu aktualnego profilu.
Import scala adresatów i lokalizacje, zachowując istniejącą bazę. Ponowny
import nie tworzy duplikatów ani nie dodaje ponownie liczników dostaw.
Ścieżkę ze spacjami można ująć w cudzysłów. Przed operacją zatrzymaj bota.
Archiwum nie zawiera jeszcze lokalnej bazy Yarrima: dostępne logi pokazują
jej licznik, ale nie pełne rekordy. Eksport należy wykonać na tym profilu.


ATAK NPC I AUTOMATYCZNA KONTYNUACJA — 1.5.5

Rozpoznany atak NPC na postać nie zatrzymuje kuriera. Dotyczy każdego
NPC, nie tylko dzikich zwierząt. Bot wykonuje kolejne kroki bieżącej trasy,
bez odwrotu, zapamiętywania miejsca ataku i ponownego wyboru paczki.
Rozpoznanie opiera się na rodzaju istoty w aktualnym GMCP albo na jawnym
zdarzeniu ataku z player=false. Walka innych istot i stare pakiety walki
z poprzedniej lokacji nie przerywają pracy. Gracz o imieniu zwierzęcia
nie jest z tego powodu uznawany za NPC.

Podczas opuszczania walki następny krok wysyłany jest po potwierdzeniu
poprzedniego (0,05 s odstępu), bez nakładania niepotwierdzonych ruchów.
Świeży koniec walki przywraca skonfigurowane tempo. Bot nie rozpoczyna
odpoczynku w miejscu ataku wyłącznie z powodu nowego niskiego HP.
Po zakończeniu walki ocenia stan; gdy potrzebna jest regeneracja, pyta
co 10 s o stan i sam wznawia ten sam kurs po odzyskaniu sił. Jeśli dotrze
do końca odcinka przed potwierdzeniem końca walki, poczeka tam na świeże
potwierdzenie, zamiast wykonywać oddanie paczki podczas niejasnego stanu.
Regeneracja wymaga HP co najmniej 80% (albo wyższego progu wynikającego
z Automatyzacji), zmęczenia do progu ruszania Chodzika, świeżych danych
własnej walki oraz tej samej postaci i potwierdzonej pozycji na mapie.
Sam upływ czasu nie oznacza wyzdrowienia. Dłuższa regeneracja nie wygasa.

Atak gracza lub przeciwnika, którego rodzaju nie potwierdzono, korzysta
z oddzielnej reakcji: zweryfikowany odwrót po już przebytej krawędzi,
zapamiętanie zagrożenia, regeneracja i automatyczny objazd. Historia
odwrotu ma maksymalnie 32 potwierdzone kroki. Brak aktualnego wyjścia,
niepotwierdzony ruch, śmierć lub utrata sesji nie są uznawane za udane
przejście. Przy braku objazdu po regeneracji bot sam sprawdza trasę
co 30 s, zachowując tę samą paczkę. Ręczny STOP zawsze działa.

GÓRY SZARE I LAS LOREN

Planer wyklucza znane dzikie lokacje Gór Szarych oraz Las Loren już
przed wyborem paczki, również przy obliczaniu kosztu i zmianie poczty.
Filtr obejmuje zwykłe kierunki, objazdy i stare plany sprawdzane ponownie
przed krokiem. Nie blokuje całego Parravon ani traktu przełęczy Montdidiera.
Poprzednia blokada samych komend wspinaczki była niewystarczająca.
Nie zmienia mapy globalnej ani ustawionych przez gracza blokad.

Testy wykonywano offline z rzeczywistymi modułami beta.13 oraz symulowaną
grą i mapą. Nie przeprowadzono próby na żywej postaci ani serwerze.
Pełne wyniki i analiza zdarzenia: dokumentacja/TEST_REPORT.txt oraz
ANALIZA_WALKI_172301.txt. Automatyka nie jest gwarancją uniknięcia śmierci.


WYBÓR PACZEK WEDŁUG SREBRA NA MINUTĘ — 1.5.6

  /paczki tryb zarobek     Wybieraj najwyższą przewidywaną zapłatę/minutę.
  /paczki oferty           Pokaż ETA, srebro/minutę, podstawę i ranking.

To domyślny tryb. Zachowane ustawienie zarobek automatycznie używa nowego
rankingu. Tryb zaplata nadal stawia najwyższą kwotę na pierwszym miejscu,
a lekkie najmniejszą masę; przy remisie oba korzystają z nowej stawki czasu.
Limit kilogramów, dostępność i kompletna obsługiwana trasa są sprawdzane
przed porównaniem opłacalności. Wyższa zapłata nie odblokowuje zakazanego
skrótu ani nie zwiększa limitu wagi.

Stawka = zapłata w srebrze / przewidywany czas pełnego kursu w minutach.
Przelicznik gry: 1 złota = 20 srebrnych = 240 miedzianych monet.
Dla NPC czas obejmuje dojście, odbiór/wydanie paczki, zapłatę, obsługę
plecaka i powrót do urzędu nadania. Dostawa do innej poczty kończy się
w filii docelowej — nie dolicza fikcyjnego powrotu do dawnej placówki.
Oznaczenie [x6] jest liczbą dostępnych zleceń. Bot niesie jedną paczkę,
więc nie mnoży samej zapłaty przez sześć.

Pierwszy szacunek korzysta z liczby rzeczywistych kroków, bieżącego tempa,
bram, obsługiwanych przepraw i oczekiwania na okresowo obecnego adresata.
Waga pokoju mapy i umowny koszt promu nie są sekundami. Robocze założenia
przed pomiarami: odpowiedź kroku 0,35 s; obsługa bramy 15 s; przeprawa
z oczekiwaniem 180 s; obsługa paczki 8 s; okresowy adresat dodatkowo 60 s.
Dochodzi skonfigurowane tempo, kolejka przejścia przez bramę oraz minimum
0,5 s po przedstawieniu się. Te liczby są oznaczonym szacunkiem, a nie
potwierdzonym rozkładem rejsów czy czasem pojawiania się Annibale.
Przy kilku możliwych lokacjach NPC pokazuje niepewność; pierwsza geometria
odpowiada lokacji, którą rzeczywiście wybierze nawigacja.

Bot sam poprawia ETA po ukończonych kursach. Pomiar zaczyna się przed
komendą wyboru paczki i kończy dopiero po jej potwierdzonym oddaniu,
wypłacie, rozliczeniu chowania monet oraz rzeczywistym powrocie do
właściwej poczty albo osiągnięciu filii docelowej. Obejmuje rzeczywiste
czekanie na bramy, prom, NPC i automatyczny odpoczynek ze zmęczenia.
Pierwsze dwa pomiary są mieszane z pierwotnym szacunkiem; od trzeciego
stosowane jest wygładzane własne doświadczenie. Zmiana tempa przelicza
wykonane zwłoki marszu i bram; nie mnoży całego czasu oczekiwania na statek.
Otwarte i zamknięte bramy uczą również faktycznej liczby zwłok przejścia.

Pomiary są osobne dla postaci, urzędu nadania, pełnego adresata, masy
paczki i wariantu trasy. Cięższa paczka nie przejmuje bezpośrednio czasu
lżejszego wariantu. Nie ma wymyślonego współczynnika szybkości na kilogram:
różnice odpoczynku wynikają z ukończonych kursów. Nowy wariant zaczyna od
jawnego szacunku. Zmiana trasy lub przeprawy nie odtwarza starego pomiaru.

Nie uczy czasu z kursów ręcznych, przerwanych STOP, rozłączeniem, reloadem,
zmianą tempa, niepotwierdzonym odbiorem/oddaniem/wypłatą lub walką zmieniającą
rytm marszu. Sam kurs po ataku NPC nadal jest kontynuowany zgodnie z 1.5.5;
wykluczany jest wyłącznie taki pomiar czasu, nie dostawa. Po wznowieniu
zapisanego kursu nie dolicza czasu spędzonego poza grą.

Panel pokazuje liczbę pomiarów i wariantów tej postaci. /paczki oferty
pokazuje ostatnią kompletną ocenę tablicy: ETA całego kursu, stawkę sr/min,
liczbę pomiarów lub szacunek, ranking i przyczynę odrzucenia. To migawka;
zmiana tempa i nowe pomiary wpłyną na wybór przy kolejnej ocenie tablicy.
Podgląd nie wydaje komend gry i nie zmienia trwającego zlecenia.

Czasy są zachowane przez przeładowanie w tym profilu. Nie są częścią
przenośnej bazy /paczki baza eksport: inne postacie uczą się własnych
osiągów. Dotychczasowa baza NPC/poczt, kurs i ustawienia pozostają dostępne.
Brak kanonicznej tożsamości umożliwia jedynie szacunek, nigdy zapis pomiaru
pod zgadywanym imieniem. Ocena dotyczy zapłaty z tablicy; nie jest obietnicą
stałego zarobku ani dokładnego czasu przy zmiennych warunkach gry.


KARAK VARN I STATEK KAHN-GAD — 1.5.7

W Karak Varn działającym celem zleceń jest Poczta, hash c55c2924e506dd7f.
Stary Urzad pocztowy w Karak Varn (3de8d58adb6dbe9b) nie przyjmuje
paczek i nie ma tablicy zleceń. Nie jest już celem ani alternatywną
placówką. Obie pisownie Karak Varn/Karak-Varn oraz starsze aliasy
Królestwa Krasnoludów prowadzą do działającej poczty. Katalog ma 24
placówki, ponieważ usunięto ten pozorny duplikat.

Jeśli rozpoczniesz pracę bez nierozliczonej paczki w starym budynku,
bot przejdzie do działającego. Dotyczy to także przycisku pracuj tutaj
oraz wznowienia pustego kursu ze starym celem. Zapisana paczka do Karak
po /paczki wznow zachowuje prawdziwy urząd nadania i trafia do dobrego
adresata bez ponownego odbioru. Aktualizuj cały folder i użyj /przeladuj,
żeby zmieniły się również rejestr i planer, nie tylko panel.

Przejście Błękitna Wstęga ↔ Karak Varn używa osobnego sterownika Kahn-Gad:
1. Dojście do właściwej przystani zwykłym traktem.
2. Oczekiwanie na świeże przybicie statku. Jeśli statek był już przy
   brzegu przed rozpoczęciem obserwacji, bot może poczekać na kolejny cykl.
   Samo oczekiwanie na potwierdzonej przystani nie wygasa.
3. Potwierdzone wyjęcie monet ze skonfigurowanego pojemnika lub własnego
   wykrytego plecaka. Plecak jest otwierany przed wyjęciem i zamykany po nim.
4. Jeden kup bilet, następnie wsiadz na statek. Ogólny komunikat o podaniu
   biletu innej/kupującej osobie nie potwierdza naszego wejścia.
5. Własne Wchodzisz po trapie na statek oraz właściwy pokład GMCP/mapy.
   Po wejściu monety wracają do plecaka, przez potwierdzaną sekwencję.
6. Odpłynięcie, nowe przybicie, zejdz ze statku i potwierdzenie właściwego
   brzegu. Nie wysiada na początkowym przybiciu ani na podstawie upływu czasu.
7. Dalszy marsz i doręczenie; w przeciwnym kierunku ten sam mechanizm.

Etykiety mapy statek/prom nie są wysyłane jako zwykłe komendy. Planer
przed wyborem paczki sprawdza oba brzegi, pokład i dalsze odcinki.
Brak elementów przeprawy nie odblokowuje trasy przez góry. Wykluczono
122 dzikie pokoje Gór Czarnych i zachodnie wejście w skrót; zachowano
Trakt w Gorach Czarnych, przystanie oraz wnętrza Karak Varn.

Przeprawa łączy się z obsługiwanym promem Grismerie, gdy cała relacja
wymaga obu statków. ETA uwzględnia każdą przeprawę. Cena biletu Kahn-Gad
nie wynika z dostarczonego logu; nie jest zgadywana. Ranking dla takiego
kursu pokazuje zapłatę/minutę przed kosztem biletu.

STOP anuluje wszystkie dalsze komendy. W tej samej sesji klienta jawne
wznowienie po wysłanym zakupie nie kupuje biletu ponownie; po świeżym
przybiciu próbuje wejść z istniejącym biletem. Nie jest to trwały dowód
zakupu po pełnym reloadzie/disconnect. Przy odtwarzaniu na znanym pokładzie
bot ustala właściwy brzeg przez potwierdzone zejście. Jeśli to brzeg
początkowy, wykonuje kolejną przeprawę do celu. Nie zgaduje orientacji
na podstawie starego tekstu. Automatyczny odpoczynek na pokładzie
zachowuje ten sam rejs bez drugiego zakupu.

Jeżeli zmęczenie przerwie samo wyjmowanie monet, wznowienie poczeka na
potwierdzenie tej operacji. Po spóźnionym własnym potwierdzeniu monety
są już w rękach: bot nie wyjmuje ich drugi raz, tylko kontynuuje kurs.
Niepotwierdzony transfer nie jest traktowany jak dokonany.

Analiza źródłowego logu: dokumentacja/ANALIZA_KARAK_181431.txt.
Testy obu kierunków i pełnych dostaw wykonywano offline z rzeczywistymi
modułami beta.13. W dostarczonym logu kierunek Błękitna Wstęga → Karak
występuje dwukrotnie; kierunek odwrotny potwierdzono w symulacji.


WERSJA 1.5.8 — SZUKANIE ADRESATA W MIESCIE

Dla jednoznacznie rozpoznanego NPC w potwierdzonym miescie bot sprawdza
swieze obserwacje, znane miejsca i dalsze dostepne lokacje tego miasta.
Dotyczy to m.in. wedrujacego Torquato di Assemani. Nie wymaga nowej komendy.
Po pelnym obchodzie bez adresata czeka 30 s i ponawia poszukiwania.

Granice wyznacza area_id z bazy swiata Chimery; przeszukiwane sa mapowe
polaczenia zwyklymi kierunkami wewnatrz tego obszaru. Uwzglednia miasto
i jego potwierdzone budynki. Nie wykorzystuje przejsc specjalnych, statkow
ani skrotow przez inny obszar. Zachowuje blokady mapy i wylaczone zagrozenia.
Pokoje o nieznanych danych lub nieoznaczonym terenie na zewnatrz nie sa
dodawane do obchodu. Brak wystarczajacej mapy/bazy swiata ogranicza szukanie
do dotychczasowego mechanizmu znanych miejsc; bot nie zgaduje granic miasta.

Obecnosc adresata jest ponownie sprawdzana podczas przygotowania oddania.
Jednoznaczna odpowiedz gry o nieobecnosci uruchamia szukanie kolejnego
miejsca z zachowaniem paczki, poczty nadania i limitu. Nie powoduje serii
oddaj paczke w pustym miejscu. Niepotwierdzone przeniesienie paczki lub
monet nadal wymaga wyjasnienia rzeczywistego stanu, zanim bot ruszy dalej.

Tempo obchodu korzysta z /paczki tempo; kazdy krok wymaga potwierdzenia.
/bot stop i /paczki stop przerywaja poszukiwania. Annibale nadal czeka
na swoim stanowisku kapitana, zamiast uruchamiac obchod miasta.

Gdy znanych jest kilka miejskich miejsc NPC, ranking zawiera dodatkowe
30 s rezerwy szukania. Jest to poczatkowy szacunek, nie rozklad wedrowki.
Potwierdzone pomiary kursow nadal aktualizuja model czasu.

Wtyczka Chimera Reconnect Paczki 1.0.0 moze pozostac zainstalowana obok.
Podczas rozlaczenia szukanie pozostaje czescia aktywnego kursu; po swiezym
logowaniu tej samej postaci wznowienie ponownie wyliczy miejsca do sprawdzenia.


WERSJA 1.5.9 — PAMIEC BEZ TOZSAMOSCI I BRAK WORLD.DB

Kurier uzupelnia stary wpis zawierajacy tylko miejsca udanych doreczen
na podstawie jednoznacznej pelnej tozsamosci z /npc. Samo podobne imie
nie wystarcza; czesciowe lub sprzeczne metadane nie sa automatycznie
przypisywane do innej osoby. Bazy kuriera nie trzeba usuwac ani ponownie
importowac. Nowe potwierdzone dostawy nadal ucza kolejnych miejsc.

Gdy przeniesiona baza nie zawiera tozsamosci, a lokalny katalog nie zna
jeszcze NPC, historia udanej dostawy pozwala rozpoczac szukanie w znanym
miescie. Bot przedstawia sie napotkanym NPC; oddanie wymaga potwierdzenia
pelnego adresata lub jednoznacznej tozsamosci poznanej w ten sposob.

Do wyszukiwania dodano zapasowe publiczne metadane miast wedlug dokladnych
hashy: 21 obszarow i 2127 lokacji. To dane o terenie i obszarach, bez NPC,
postaci czy bazy adresatow gracza. Dzialaja tez, gdy glowny modul world
nie moze odczytac world.db. Dostepne aktualne dane swiata maja pierwszenstwo,
a jawnie wykluczony teren nie jest nadpisywany zapasowym wpisem.

Mapa danego profilu nadal musi zawierac pokoje i zwykle polaczenia miedzy
nimi. Publiczne metadane nie instaluja mapy i nie odkrywaja nieznanych wyjsc.

Panel /paczki pokazuje wersje 1.5.9 i tryb szukania. Polecenie:
  /paczki diagnostyka
pokazuje wersje silnika i modulu NPC, powod wyboru trybu, tozsamosc adresata,
obszar oraz zrodlo metadanych miasta (world/bundled/mixed). Nie wymusza
startu, oddania, przenoszenia rzeczy ani kasowania pamieci.

Aktualizuj CALY folder, wszystkie 24 pliki, potem /przeladuj. Wznowienie
niedokonczonej dostawy: /paczki wznow. Nie wybieraj nowej poczty przed
rozliczeniem rzeczywiscie niesionej paczki. Baza, statystyki i kurs zostaja
zachowane podczas aktualizacji.


WERSJA 1.5.10 — BOREG I DOPISKI POCHODZENIA

W obu logach z 25 pazdziernika bot poprawnie docieral do Borega, lecz
opuszczal kuznie po przedstawieniu. Poprawiono regresje rozpoznawania
tozsamosci z 1.5.9: Boreg Khrazaksson z tablicy oraz przedstawienie
Boreg Khrazaksson z Karak Izor oznaczaja tego samego adresata.
Regula dziala takze dla innych nazw z dopiskiem pochodzenia z/ze.
Nie dopasowuje dowolnego poczatku nazwiska ani przyrostka Senior;
kilku zgodnych NPC nadal wymaga jednoznacznego ustalenia tozsamosci.

Aktualizacja na OBU profilach:
  /bot stop
Nadpisz caly folder chimera_wtyczki/chimera_paczki (24 pliki). Nastepnie:
  /przeladuj
Poczekaj do KONCA przeladowania wszystkich modulow. Dopiero wtedy:
  /paczki diagnostyka
  /paczki wznow
Diagnostyka ma pokazac Paczki 1.5.10, silnik 1.5.10 i NPC 1.5.10.
Zapisana baza i kurs sa zachowane; nie uzywaj reset do tej aktualizacji.
Jesli paczka zostala juz rzeczywiscie oddana recznie, gra potwierdzila
doreczenie oraz wyplate, a skrypt nadal pokazuje niesiona paczke,
korzystaj z opisanego wyzej rozliczenia recznego zamiast ponownego odbioru.

Pelna analiza obu logow jest w dokumentacja/ANALIZA_BOREG_102138_095515.txt.
Testy odtwarzaja sytuacje Yarrima i Morrida z rzeczywistymi modulami Chimery
i symulowanymi odpowiedziami gry; nie testowano na zywej postaci.


WERSJA 1.5.11 — PLYNNE PLANOWANIE, MICHAEL I OPOZNIONE OTWARCIE

Ocena ofert wykonuje wyszukiwanie w krotkich porcjach, oddajac sterowanie
Mudletowi. W tej ocenie nie wywoluje nieprzerywalnego getPath; korzysta
z ograniczonego przeszukiwania zwyklych, obslugiwanych polaczen mapy.
Oferty do tego samego adresata wspoldziela jedno wyznaczenie celu,
a powtarzane odcinki sa pamietane tylko na czas aktualnego zadania.
Pojedyncze zadanie ma ograniczona pamiec; po zakonczeniu lub anulowaniu
wyniki sa zwalniane. Rzeczywisty marsz nadal sprawdza aktualna trase.

Krotki lokalny kurs pomija promy, ktore juz wedlug minimalnego kosztu
nie moga dac lepszego wyniku. Wymuszone przeprawy Nuln-Quenelles oraz
Karak Varn pozostaja obslugiwane. Po odebraniu wybranej paczki kurier
korzysta z juz ustalonego adresata, zamiast ponownie liczyc caly ranking.
Odtwarzanie celu zapisanego kursu rowniez moze oddawac sterowanie.

STOP, rozlaczenie, zmiana postaci, ruch reczny, przeladowanie lub przejecie
sterowania przez innego bota anuluja oczekujace obliczenia. Zmiana limitu,
strategii, tempa lub automatycznej zmiany poczty uniewaznia ranking.
Gdy ktos bierze paczke z tablicy podczas liczenia, bot ponownie ja czyta.

Don Michael Tommasino jest rozpoznawany jako adresat Michael Tommasino.
Dopuszczony jest dokladnie zaobserwowany tytul Don; inne nazwisko, Senior
i kolizje tozsamosci nadal sa odrzucane. Baza nie wymaga resetu ani importu.

Na potwierdzenie otwarcia pojemnika bot czeka do30s; po pierwszym krotszym
limicie wypisuje informacje o oczekiwaniu i dalej czeka na wlasna odpowiedz.
Nie powtarza komendy ani nie przenosi paczki lub monet przed odpowiedzia.
STOP nadal anuluje oczekiwanie. Zasady niepotwierdzonych przeniesien rzeczy
pozostaja zachowane.

Aktualizacja: /bot stop, nadpisanie CALEGO folderu24plikow, /przeladuj,
odczekanie do zakonczenia ladowania, /paczki diagnostyka, /paczki wznow.
Paczki, silnik i NPC maja wskazywac1.5.11. Statystyki i kurs pozostaja zapisane.

Diagnostyka pokazuje liczbe aktywnych zadan, porcje i oddania sterowania,
a takze najdluzsza zmierzona porcje CPU od wczytania. Budzet okolo5ms
jest sprawdzany miedzy punktami kontrolnymi, wraz z limitem pracy;
pojedynczego wywolania API lub bazy danych nie mozna przerwac. Nie jest
to obietnica dokladnego maksymalnego opoznienia systemu. Polecenia recznego
podgladu /paczki npc i /paczki poczty oraz wykonanie marszu zachowuja
dotychczasowe planowanie. Po aktualizacji warto porownac ponowny pomiar
najwiekszej blokady klienta; czas rank w profilerze moze obejmowac przerwy
pomiedzy porcjami. Nie dodawaj czasow zagniezdzonych wywolan.


WERSJA 1.5.12 — FRYDERIK, NIKOLAUS I ZAPIS PRZEPRAWY

Fryderik Miecznik z tablicy jest rozpoznawany jako Fryderik z Nuln
z przedstawienia i katalogu NPC. To dokladne, potwierdzone powiazanie
pelnych nazw; samo podobne imie nie wystarcza. Regula obejmuje oba
profile, stara pamiec dostaw, import samych lokacji i pierwsze spotkanie.
Bazy nie trzeba usuwac ani ponownie importowac.

Nikolaus Schmidt: poczta i warsztat sa po przeciwnych stronach Soll.
Most jest zwykla droga kuriera, lecz nie nalezy do obszaru patrolu
miejskiego wedlug metadanych. Przed rozpoczeciem patrolu bot sprawdza,
czy znane miejsce NPC jest osiagalne w jego biezacej czesci miasta.
Jesli nie, idzie zwykla kontrolowana trasa do znanego miejsca, a tam
sprawdza adresata lub rozpoczyna patrol. Nie rozszerzono patrolu na
nieznany teren, gory ani las; blokady mapy pozostaja respektowane.

Kahn-Gad zapisuje etap przeprawy osobno dla kanonicznej postaci z GMCP:
zweryfikowane brzegi, zamierzony kierunek, etap biletu/wejscia i obsluge
reszty. Zapis nie zawiera timerow, numerow mapy ani danych logowania.
Po rozlaczeniu lub reloadzie potwierdzonego schowania monet nie ponawia.
Wlasne potwierdzenie monet odebrane przed zamknieciem plecaka lub po STOP
aktualizuje stan, lecz samo nie uruchamia anulowanego bota.

Podczas braku polaczenia statek moze zawrocic. Po odtworzeniu bot czeka
na nowe przybicie, schodzi pojedynczo i sprawdza rzeczywisty brzeg.
W razie trafienia na przeciwny brzeg wykonuje kontrolowana korekte.
Starego tekstu przybicia nie traktuje jako nowego potwierdzenia.
Na starszym zapisie bez etapu rejsu opcjonalne porzadkowanie monet
na pokladzie moze odlozyc do wyplaty za paczke. Nie zglasza wtedy
fikcyjnego potwierdzenia schowania i nie zatrzymuje rejsu na Wloz co?.
Niepotwierdzone przeniesienie nadal nie jest slepo powtarzane.

Poprawiono tez reload przy nierozstrzygnietym wejsciu/zejsciu i kroku:
sprzatanie starego modulu nie tworzy timerow w zamknietym zakresie.

Automatyczne wznowienie po nowym logowaniu wymaga wlaczonego dodatku
Chimera Reconnect Paczki oraz aktywnego kursu w chwili rozlaczenia.
/knet on wlacza, /knet off wylacza; /paczki_net jest aliasem rezerwowym.
Reczny STOP lub przejecie sterowania komenda do gry anuluje taki zamiar.
Samo odczytanie zapisu albo instalacja na pokladzie nie startuje bota.

Aktualizacja OBU profili:
  /bot stop
Nadpisz CALY folder chimera_wtyczki/chimera_paczki (24 pliki Lua), potem:
  /przeladuj
Poczekaj do zakonczenia ladowania wszystkich modulow i wykonaj:
  /paczki diagnostyka
  /paczki wznow
Paczki, silnik i NPC maja wskazywac 1.5.12. Kurs, baza i statystyki zostaja.
Moze byc zachowana niesiona paczka; nie jest potrzebny reset bazy.
Diagnostyka pokazuje tez dokladna nazwe i tytul NPC oraz zapis przeprawy.

Pelna analiza: dokumentacja/ANALIZA_FRYDERIK_STATEK_121722_130539.txt.
Nie ustalono przyczyny komunikatu Remote host closed; poprawka obejmuje
odzyskanie kursu i kontynuacje przeprawy po takim zdarzeniu.


1.5.13 — aktualizacje GitHub

Repozytorium: https://github.com/gurninson-sketch/chimera-paczki
Pierwsza instalacja: zastap caly folder chimera_paczki (25 plikow Lua)
i wykonaj /przeladuj. Potem /paczki aktualizuj sprawdza nowe wydania,
/paczki autoaktualizacja on|off steruje automatem,
/paczki aktualizacje status pokazuje jego stan. Instalacja czeka na stop
wszystkich botow, koniec walki i zakonczenie operacji kuriera.
Aktualizator nie zatrzymuje kursu. Baza i zapisane dane sa zachowane.

1.5.14 — miejscowe przed międzymiastowymi
----------------------------------------
Nowa stała kolejność zastępuje starsze opisy trybów zarobek/zaplata/lekkie.
Najpierw miejscowe z aktualnej poczty, po każdej dostawie powrót i odczyt
tablicy; potem międzymiastowe poczta -> poczta. W nowym mieście ponownie
miejscowe. Międzydomenowe/międzykrainowe nie są wybierane automatycznie.
W grupie: numer tablicy. Waga tylko jako limit, cena i ETA informacyjne.
Nie trzeba resetować bazy ani zapisanego kursu.

1.5.16: /paczki szukanie 5 ustawia minuty szukania po mieście.
Po limicie powrót, potwierdzony zwrot i pomijanie adresata przez 30 min.
Przerwa zachowuje stan kursu. Szczegóły w README.md.

WSPÓLNA BAZA ADRESÓW OD 1.5.19

Publiczny katalog GitHub: data/addresses.json. Trzy źródła: Groro, Yarrim,
Morrid; początkowo 63 adresatów i 69 lokalizacji.
/paczki baza aktualizuj — pobierz i scal z lokalnymi odkryciami.
/paczki baza status — sprawdź wynik.
/paczki baza synchronizacja on|off — automatyczne sprawdzanie po 45 s
od załadowania i co 6 godzin. Import czeka na zatrzymanie botów oraz
rozliczenie operacji; wcześniej zapisuje kopię lokalnej bazy.
Nowe eksporty dodaj do data/address_sources/ w repozytorium GitHub.
GitHub Actions waliduje i scala źródła. Bot sam nie wysyła eksportów.

START NA POCZCIE PO PEŁNYM PRZEŁADOWANIU — 1.5.20

Brak bieżącej pozycji po /przeladuj uruchamia odświeżenie GMCP także
bez zapisanego kursu, np. na poczcie Campogrotta. Bot kontynuuje po
potwierdzeniu aktualnej postaci i zgodności lokacji z mapą.
/paczki poczta tutaj przy nieznanej pozycji również odświeża dane.
/paczki diagnostyka pokazuje ID lokacji GMCP, pokój mapy i zgodność.
Brak lokacji na mapie jest osobnym problemem; baza adresów nie zastępuje mapy.

ANNIBALE Z BAZY WSPOLNEJ — 1.5.21

Sam potwierdzony adres mola bez tozsamosci NPC nie blokuje juz
przedstawienia sie obecnym postaciom. Kurier sprawdza pelna tozsamosc
Annibale przez aktualne GMCP i baze /npc przed oddaniem paczki.
Zmiana obecnych NPC pozwala ponowic przedstawienie, najwyzej raz na 10 s.
Sam opis, obcy NPC ani gracz nie uprawniaja do oddania. Bot pozostaje
na molo; nie kupuje biletu i nie wsiada na statek. STOP anuluje oczekiwanie.

BRUNO ROTTEL — NIEMY PATROL KREUTZHOFEN, 1.5.22

Log z 27.10.2026 potwierdza trzy doreczenia przy patrolu z czterech opisow:
  schludny orlonosy mezczyzna
  podekscytowany orlonosy mezczyzna
  hardy czarnooki mezczyzna
  niebieskooki starszy mezczyzna
Patrol nie odpowiada na przedstawienie sie. Skrypt nie przypisuje
ktoregokolwiek opisu do zmyslonego imienia ani identyfikatora NPC.
Swiezy kompletny patrol w Kreutzhofen uprawnia do proby oddania paczki
Bruno; dopiero gra potwierdza doreczenie i wyplate. Niepelna grupa,
gracz zamiast NPC lub niejednoznaczny opis nie wystarczaja.
Po odejsciu patrolu bot kontynuuje poszukiwanie w miescie. Zachowany
jest limit szukania i zwrot paczki przy dluzszej nieobecnosci.

Do bazy dodano potwierdzone doreczenia na dziedzincu garnizonu
(5f8910ee564c903e) i przy poludniowej stronie mostu (4fa405b9e7ecef09).
To miejsca spotkan wedrujacego patrolu, nie stale stanowisko Bruno.
Trzy dokladnie zweryfikowane miejskie pokoje, ktorym publiczna mapa
nie podaje terenu, lacza dojscie do garnizonu. Przeprawa przez Soll
pozostaje poza rozszerzeniem miejskiego obchodu. Mapa profilu nie
jest modyfikowana, a aktualne blokady i jawny teren lesny/gorski
nadal wykluczaja dany krok.
