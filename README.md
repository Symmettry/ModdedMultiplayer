# Modded Multiplayer (Balatro)

A custom multiplayer mod built specifically for **ultra-modded Balatro environments**.

This is **not** a vanilla-friendly or ranked-style multiplayer mod: it is designed to work alongside heavy modpacks and handle the complexity that comes with them (custom cards, abilities, scaling numbers, etc).

## Overview

This mod enables real-time multiplayer runs by synchronizing game state between players using a **server + WebSocket architecture**.

- Created in an **ultra-modded environment**
- Attempt for full support of **custom cards, abilities, and scaling values**
- Uses **state syncing + event streaming** rather than just seed syncing
- Designed to be **resilient to mod differences and edge cases**

## Features

- Party system (create / join via code)
- Real-time synchronization via WebSockets
- Shared run state (deck, stake, seed)
- Boss synchronization (progress, score, hands, etc.)
- Life system across players
- Card state syncing (including modded cards)

## Native WebSocket Dependency

This mod **uses a native WebSocket implementation**.

Lua-only WebSocket libraries were avoided because they are:

- Too slow
- Bug-prone
- Inefficient
- Annoying to make...

Instead, this uses:
[https://github.com/Symmettry/ws_native](My Native WS .dll/.so)

I apologize for resorting to a native hook inside of a Balatro mod of all things, but it's worth it!!!
If you don't trust it, you can compile it yourself with the github! :3

## Configuration

Set the server endpoint in the in-game configuration; there's an endpoint in there and you can set it up based on who's hosting a server

## Installation

1. Install dependencies:
- Steamodded
- Amulet

2. Add this mod to your mods folder

5. Start or find a server (https://github.com/Symmettry/ModdedMultiplayer-Server (publishing after I clean it up))

6. Launch the game -> `ONLINE`

## Bugs or issues

Please report any bugs or issues you find in the Issues tab of my github page, or contact me @lilyorb on discord
If you encounter a mod that has an issue with this modpack, please also make an Issue for it so I can add compatibility
Vanilla will probably be buggy since I didn't test this with vanilla in mind.

## Credits

- Author: Symmettry/lily
- Native WebSocket: Symmettry/ws_native