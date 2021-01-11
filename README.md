# gmod-metaconcord

## [Objective](https://hackmd.io/SwE_rpqESKSfV0LMvBd0Kw?both)

## Requirements

[GWSockets](https://github.com/FredyH/GWSockets)

## Setup

You will need to create two files:

- `garrysmod/data/metaconcord-endpoint.txt` with the hostname and port to the websocket server that [node-metaconcord](https://github.com/Metastruct/node-metaconcord) will host.
- `garrysmod/data/metaconcord-token.txt` with a custom secret of your choosing that [node-metaconcord](https://github.com/Metastruct/node-metaconcord) will accept for incoming connections.

Of course, you'll need the [node-metaconcord](https://github.com/Metastruct/gmod-metaconcord) service to be running on your server to allow for communication with this add-on  
