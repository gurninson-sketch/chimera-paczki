# Zmiany

## 1.5.20

- Start na poczcie po pełnym przeładowaniu, także bez zapisanego kursu: odświeżenie GMCP i oczekiwanie na potwierdzoną lokację zamiast błędnego komunikatu o trasach Nuln.
- `/paczki poczta tutaj` odświeża brakującą lub niezgodną pozycję przed rozpoznaniem urzędu.
- Diagnostyka pokazuje lokację GMCP, pokój mapy i zgodność identyfikatorów; osobny komunikat dla lokacji brakującej na mapie.
- Regresje Campogrotta po restarcie, brak mapy, niezgodny pokój i STOP przed nadejściem danych.

## 1.5.19

- Publiczna wspólna baza: 63 adresatów i 69 lokalizacji z trzech zatwierdzonych eksportów Groro, Yarrim i Morrid.
- Walidacja źródeł i deterministyczne scalanie katalogu przez GitHub Actions; raport konfliktów tożsamości.
- `/paczki baza aktualizuj`, `baza status`, `baza synchronizacja on|off`; automatyczne pobieranie po starcie i co 6 godzin.
- Import przy zatrzymanych botach i po rozliczeniu operacji, kopia przed scaleniem i zachowanie lokalnych odkryć.
- Publikacja źródeł zatwierdzona przez użytkownika; bot pobiera katalog, a nowe eksporty dodaje się do repozytorium samodzielnie.

## 1.5.18

- Zmiana numeracji podczas odbioru: paczka dla innego adresata zostaje zwrócona bez wyznaczania jego trasy, także jeśli adres jest znany. Własne potwierdzenie zwrotu odświeża tablicę; brak blokady adresata po takim zwrocie.
- Zapis i wznowienie zwrotu niezamówionej lub nierozpoznanej paczki bez rozwiązywania trasy do jej adresata.
- Po doręczeniu w Ebino: bez prób nadawania, sprawdzenie bezpiecznego powrotu do ostatniej poczty nadającej przesyłki; dopiero przy braku tej drogi szukanie innej placówki.

- Bank wyłącznie przy okazji pobytu na poczcie Nuln, po rozliczeniu paczki; brak zmiany miasta lub trasy z powodu terminu.
- Domyślny odstęp 120 minut; zaległy termin i `bank teraz` czekają na postój na poczcie Nuln.
- Migracja dawnego domyślnego odstępu 30 minut i jednorazowe wyznaczenie terminu; inne ustawione odstępy zachowane.
- Zapisana wizyta może wznowić ruch tylko w korytarzu poczta–bank Nuln; dawny dojazd z innego miasta zostaje odłożony.

## 1.5.17

- Okresowa denominacja w banku Nuln, domyślnie co 30 minut; `/paczki bank <minuty>`, `teraz`, `status`, `on/off`.
- Wizyta po rozliczeniu paczki, potwierdzone wyjęcie monet, własne potwierdzenie `zdenominuj`, schowanie i powrót na pocztę Nuln.
- Termin i etap wizyty zachowane osobno dla postaci; STOP, brak odpowiedzi i przerwana wymiana blokują dalsze polecenia.
- Ebino jako punkt doręczeń bez nadawania; trwała pamięć potwierdzonych placówek bez tablicy.
- Podsumowanie ofert przed szukaniem kolejnej poczty i wybór pierwszej bezpiecznej placówki bez przeliczania całego katalogu.
- Ujednolicona instrukcja wznowienia po rozłączeniu: `/paczki wznow`.

## 1.5.16

- Limit całego szukania po mieście: domyślnie 5 minut; `/paczki szukanie <minuty>`.
- Po limicie powrót do urzędu nadania, wyjęcie paczki i zwrot; nowe doręczenie dopiero po potwierdzeniu gry.
- Pomijanie pełnego adresata przez 30 minut, niezależnie od wagi/nagrody; stan osobny dla postaci i poczty.
- Rozpoznawanie rzeczywistego potwierdzenia ręcznego i automatycznego zwrotu; zachowanie zamiaru zwrotu i wykorzystanego czasu po przerwie.
- Pomijanie lokalu zamkniętego do rana podczas bieżącego patrolu bez ponawiania wejścia ani trwałej zmiany mapy.

## 1.5.15

- Pobieranie manifestu i kodu przez downloadFile; obsługa przekierowań GitHuba przez dopasowanie unikalnej ścieżki pliku.
- Osobne żądania, sprzątanie plików tymczasowych i odrzucanie spóźnionych odpowiedzi.
- Limit 60 sekund ze wskazaniem pobieranego etapu i rzeczywistej przyczyny błędu.
- Zachowane limity rozmiaru, SHA-256, walidacja Lua oraz wycofanie nieudanej instalacji.
- Przy aktualizacji z 1.5.13/1.5.14 użyj jednorazowo ZIP-a: stary aktualizator może ignorować przekierowane odpowiedzi.

## 1.5.14

- Stała kolejność: miejscowe przed międzymiastowymi poczta → poczta; w grupie numer na tablicy.
- Międzydomenowe / międzykrainowe wykluczone przed liczeniem tras.
- Brak liczenia tras międzymiastowych przy dostępnych miejscowych.
- Cena, masa i ETA nie decydują o pierwszeństwie; limit udźwigu zachowany.
- Migracja starych trybów i przyczyny odłożenia ofert.

## 1.5.13

- Osobne publiczne repozytorium i wydania GitHub Releases.
- Aktualizacje z kontrolą rozmiaru, SHA-256, kompletu plików i składni Lua.
- Odłożenie instalacji do zatrzymania botów, końca walki i zakończenia operacji kuriera; przełącznik automatycznych aktualizacji.
- Kopia poprzedniego kodu, podmiana całego folderu i sprawdzenie wyniku przeładowania.
- Zachowanie danych profilu oraz wszystkich poprawek z 1.5.12, w tym Fryderika Miecznika, trasy do Nikolausa Schmidta i wznowienia przeprawy Kahn-Gad.

## 1.5.12

Poprawna identyfikacja Fryderika z Nuln dla paczki do Fryderika Miecznika; przejście przez Soll do Nikolausa Schmidta; trwały stan przeprawy Kahn-Gad i potwierdzeń monet; bezpieczne sprzątanie przejść przy przeładowaniu.

## Wcześniejsze wersje

Historia zmian i zachowanych zachowań znajduje się w README_PL.txt. Pierwszą wersją tego repozytorium jest 1.5.13.
