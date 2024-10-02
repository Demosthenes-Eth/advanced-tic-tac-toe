# advanced-tic-tac-toe
An onchain multiplayer game of Tic Tac Toe with a twist.

#

Intended to be an onchain multiplayer game that requires little-to-know maintenance from the game developer after deployment.  Players can request new games and will be automatically matched with players waiting in the player queue.  Players can also create games with a unique seed and provide that seed to other players so that they will be guaranteed to play each other rather than a random player.  Players can wager on the game and the winner of the game receives the pot.   The game logic accounts for wins, losses, ties, and resignations.

Gameplay is Tic Tac Toe, but with a twist.  Players will still places X's and O's to occupy squares in the 3x3 Tic Tac Toe grid. However, those markers will also have an RGB color value which must be specified by the player when played.  The game logic then checks the RGB value of the marks occupying any of the neighboring squares to the one just occupied. If the sum of the RGB values of the two neighboring occupied squares equals or exceeds RGB(255,255,255), ie "White", then the neighboring square gets cancelled out and becomes empty again.

This adds a layer of strategic complexity to the game.  Instead of just worrying about which square to occupy, players must also account for the color values of their opponents squares and of their own.  It also helps to counteract the influence that turn order can have on the outcome of traditional Tic Tac Toe.

# Current Issues
I'm in the process of testing and debugging the smart contract.  Currently, the biggest issue is that the game logic which calculates whether a player has won the game is prematurely ending the game and incorrectly declaring a winner.
