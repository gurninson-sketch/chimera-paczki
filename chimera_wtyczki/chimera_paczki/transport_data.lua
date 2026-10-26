-- Confirmed ferry and Quenelles gate identities from the supplied logs.
-- South: one exit s; north: exits e,w. The ferry deck has no upstream hash.
-- Road paths are intentionally resolved from the live map.
return {
  ferries = {
    quenelles = {
      id = "quenelles",
      south = "894039a1680ca034",
      north = "20016d960316ba51",
      board = "wejdz na prom",
      disembark = "zejdz na brzeg",
      ticket = false,
      deck_title = "Na pokladzie promu",
      events = {
        ready = "Rzeczny prom przybija do brzegu.",
        departed = "Prom powoli odbija od brzegu.",
        arrived = "Prom powoli przybija do brzegu.",
        boarded = "Wskakujesz na poklad promu.",
        landed = "Schodzisz z pokladu promu na brzeg.",
      },
    },
  },
  gates = {
    ["060d3ff10fbd46b5"] = {
      command = "uderz we wrota",
      direction = "e",
      to = "38e60eb65905fa7b",
      wait = 5.0,
      opened = "Z glosnym trzaskiem wrota zostaja otwarte.",
      closed = "Zelazne wrota sa zamkniete na zamek!",
    },
    ["38e60eb65905fa7b"] = {
      command = "uderz we wrota",
      direction = "w",
      to = "060d3ff10fbd46b5",
      wait = 5.0,
      opened = "Z glosnym trzaskiem wrota zostaja otwarte.",
      closed = "Zelazne wrota sa zamkniete na zamek!",
    },
  },
}
