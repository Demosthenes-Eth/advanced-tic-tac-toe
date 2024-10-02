// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract TicTacToe {
    
    address payable owner;
    uint ownerBalance;
    uint feePercentage = 10;
    bool pauseState = true;

    /*Approximately 1 week on Base,
    measured in blocks*/
    uint timeOutInterval = 302400;

    struct Game {
        address payable player1;
        address payable player2;
        uint256 gameIndex;
        bytes32 gameID;
        bytes32 seed;
        //1 = player1, 2 = player2
        uint8 playerTurn;
        /*["0 = empty, 1 = player1, 2 = player2", redValue, greenValue, blueValue]
        [board spaces indexed from left to right, top to bottom]*/
        uint[4][9] boardData;
        uint gamePot;
        uint startingBlock;
    }

    struct PlayerData {
        uint[] activeGames;
        uint wins;
        uint losses;
        uint ties;
        uint resignations;
        uint balanceOf;
        uint pendingDeposits;
    }

    mapping(address => PlayerData) public playerData;

    //queue to store players waiting for a game match
    address payable [] playerQueue;
    //array storing all games
    Game [] games;

    constructor(){
        owner = payable(msg.sender);
    }

    event gameInitiated(address indexed player1, address player2, uint indexed gameIndex, bytes32 indexed gameID, bytes32 seed);
    event gameCreatedWithSeed(address indexed player1, uint indexed gameIndex, bytes32 indexed seed);
    event squareExploded(uint indexed gameIndex, bytes32 indexed gameID, uint squarePosition);
    event gameOver(uint indexed gameIndex, bytes32 indexed gameID, address victor);
    event stalemate(uint indexed gameIndex, bytes32 indexed gameID);
    event resignation(uint indexed gameIndex, bytes32 indexed gameID, address indexed resignee);
    event withdrawInitiated(address indexed to, uint amount);
    event playCompleted(address indexed player, uint indexed gameIndex, bytes32 indexed gameID, uint position, uint redValue, uint greenValue, uint blueValue);

    modifier onlyOwner(){
        require(payable(msg.sender) == owner, "Unauthorized address");
        _;
    }

    //confirms that the entered seed matches that of the specified game
    modifier seedMatch(uint _index, bytes32 _seed){
        require(games[_index].seed == _seed, "Seed does not match");
        _;
    }

    modifier isPaused(){
        require(pauseState != true, "Contract is paused");
        _;
    }

    /*modifier to verify that it's the turn of the function caller 
    and that the square they wish to occupy is currently unoccupied*/
    modifier verifyPlay(uint _index, uint _position){
        uint _currentTurn = games[_index].playerTurn;
        address payable _player1 = games[_index].player1;
        address payable _player2 = games[_index].player2;
        require((((_currentTurn == 1) && (payable(msg.sender) == _player1)) || ((_currentTurn == 2) && (payable(msg.sender) == _player2))), "Invalid play");
        require(games[_index].boardData[_position][0] == 0, "Position isn't empty.");
        _;
    }

    //function for a player to request to be matched for a game
    function requestNewGame() public payable isPaused{
        require(msg.value == 0.05 ether, "You must send exactly 0.05 ETH to start a new game");
        
        /*If no other players are currently waiting in the player queue
        add the player to the queue*/
        if (playerQueue.length == 0){
            playerQueue.push(payable(msg.sender));
            playerData[msg.sender].pendingDeposits = msg.value; // Record the deposit
            } else {
                address payable _player1 = payable(msg.sender);
                address payable _player2 = playerQueue[0];
                Game memory game;
                game.player1 = _player1;
                game.player2 = _player2;
                game.gameIndex = games.length;
                game.gameID = keccak256(abi.encodePacked(_player1, _player2, game.gameIndex));
                game.playerTurn = 1;
                // Set the game pot to the sum of both players' deposits - game fee
                uint256 totalDeposits = playerData[_player2].pendingDeposits + msg.value;
                uint256 fee = totalDeposits * feePercentage / 100;
                game.gamePot = totalDeposits - fee;
                ownerBalance += fee;
                game.startingBlock = block.number;
                games.push(game);
                
                // Remove the matched player from the queue and reset their pending deposit
                removeFromPlayerQueueAtIndex(0);
                playerData[_player2].pendingDeposits = 0;
                emit gameInitiated(_player1, _player2, game.gameIndex, game.gameID, game.seed);
            }
    }

    /*function allowing a user to create a game with an open player2 slot and a seed
    that they can share allowing another user to be matched specifically to that game*/
    function createGameWithSeed() public payable isPaused returns (bytes32 seed) {
        require(msg.value == 0.05 ether, "You must send exactly 0.05 ETH to start a new game");
        
        Game memory game;
        game.player1 = payable(msg.sender);
        game.gameIndex = games.length;
        game.gamePot = msg.value;
        game.seed = keccak256(abi.encodePacked(game.player1, game.gameIndex));
        games.push(game);
        emit gameCreatedWithSeed(game.player1, game.gameIndex, game.seed);
        return game.seed;
    }

    //function allows users to join a game via entering a unique game seed
    function joinExistingGame(uint _index, bytes32 _seed) public payable isPaused seedMatch(_index, _seed) {
        require(msg.value == 0.05 ether, "You must send exactly 0.05 ETH to join the game");
        games[_index].player2 = payable(msg.sender);
        uint256 totalDeposits = games[_index].gamePot + msg.value;
        uint256 fee = totalDeposits * feePercentage / 100;
        games[_index].gamePot = totalDeposits - fee;
        ownerBalance += fee;
        games[_index].gameID = keccak256(abi.encodePacked(games[_index].player1, games[_index].player2, _index));
        games[_index].playerTurn = 1;
        games[_index].startingBlock = block.number;
        emit gameInitiated(games[_index].player1, msg.sender, _index, games[_index].gameID, games[_index].seed);
    }

    /*helper function that removes the first user from the player queue and shifts
    all queue positions down by 1*/
    function removeFromPlayerQueueAtIndex(uint _queueIndex) internal {
        require(_queueIndex < playerQueue.length, "Index out of bounds");
    for (uint256 i = _queueIndex; i < playerQueue.length - 1; i++) {
        playerQueue[i] = playerQueue[i + 1];
    }
    playerQueue.pop();
    }

    function cancelGameRequestByIndex(uint _queueIndex) public isPaused{
        // Check if the player is in the queue
        require(playerQueue[_queueIndex] == msg.sender, "Provided address does not match index");

        // Remove the player from the queue
        removeFromPlayerQueueAtIndex(_queueIndex);

        // Refund the pending deposit
        uint amount = playerData[msg.sender].pendingDeposits;
        playerData[msg.sender].pendingDeposits = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to refund deposit");
    }

    function cancelGameRequest() public isPaused{
        // Check if the player is in the queue
        bool isInQueue = false;
        uint _queueIndex;
        for (uint i = 0; i < playerQueue.length; i++) {
            if (playerQueue[i] == msg.sender) {
                isInQueue = true;
                _queueIndex = i;
                break;
            }
        }
        require(isInQueue, "You are not in the queue");

        // Remove the player from the queue
        removeFromPlayerQueueAtIndex(_queueIndex);

        // Refund the pending deposit
        uint amount = playerData[msg.sender].pendingDeposits;
        playerData[msg.sender].pendingDeposits = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to refund deposit");
    }

    /* Allows the creator of a private game to cancel the game
    via entering their private game seed prior to a 2nd player joining*/
    function cancelGameWithSeed(uint _index, bytes32 _seed) public isPaused seedMatch(_index, _seed){
        require(games[_index].player2 == address(0), "Game is in progress");
        require(games[_index].player1 == msg.sender, "You did not create this game");
        uint amount = games[_index].gamePot;
        games[_index].gamePot = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to refund deposit");
    }

    // game function called by a player to occupy a square on the board
    function play(uint _index, uint _position, uint _redValue, uint _greenValue, uint _blueValue) public isPaused verifyPlay(_index, _position){
        if(games[_index].playerTurn == 1){
            games[_index].boardData[_position][0] = 1;
        } else {games[_index].boardData[_position][0] = 2;}
        games[_index].boardData[_position][1] = _redValue;
        games[_index].boardData[_position][2] = _greenValue;
        games[_index].boardData[_position][3] = _blueValue;
        emit playCompleted(msg.sender, _index, games[_index].gameID, _position, _redValue, _greenValue, _blueValue);
        calculateExplosions(_index, _position);
        bool victory = checkVictory(_index, _position);
        // If the play satisfies a victory condition and the game hasn't timed out
        if(victory && (block.number < games[_index].startingBlock + timeOutInterval)){
            resolveGame(_index, games[_index].playerTurn);
        /* If the play doesn't satisfy a victory condition and all squares are occupied
        or the game has timed out*/
        } else if((checkTie(_index) && !victory) || (block.number >= games[_index].startingBlock + timeOutInterval)){
            resolveTie(_index);
        // The play doesn't satisfy a victory condition but the game hasn't timed out
        } else {
            updatePlayerTurn(_index);
        }
    }

    //function calculates whether the newly occupied square causes any neighboring squares to "explode"
    function calculateExplosions(uint _index, uint _position) internal {
        /*calculate the neighbors of the square that the player has newly occupied
        and store their indices in an array*/
        uint[] memory _neighbors = calculateNeighbors(_position);
        //store the separate rgb values of the player's newly occupied square
        uint r1 = games[_index].boardData[_position][1];
        uint g1 = games[_index].boardData[_position][2];
        uint b1 = games[_index].boardData[_position][3];
        //loop over the array of neighboring squares
        for (uint i = 0; i < _neighbors.length; i++){
            //store the separate rgb values of the neighboring square
            uint r2 = games[_index].boardData[_neighbors[i]][1];
            uint g2 = games[_index].boardData[_neighbors[i]][2];
            uint b2 = games[_index].boardData[_neighbors[i]][3];
            //check whether the combined rgb values of the two squares is >= rgb(255, 255, 255) i.e. "white"
            if ((r1 + r2) >= 255 && (g1 + g2) >= 255 && (b1 + b2) >= 255){
                //change the state of the neighboring square to empty
                games[_index].boardData[_neighbors[i]][0] = 0;
                emit squareExploded(_index, games[_index].gameID, i);
            }
        }
    }

    //function checks whether the newly occupied square satisfies the victory conditions of the game
    function checkVictory(uint _index, uint _position) internal view returns (bool){
        //determines the row of the position, assumes division in solidity rounds down to 0
        int row = int(_position / 3);
        //determines the column of the position
        int column = int(_position % 3);
        //a memory array to store our boolean results
        bool [3] memory _checks;
        //a counter to manage the index for storing results in _checks
        uint j = 0;

        /*Conditional checks whether the index of the position is even.  
        If it's even, then the square is part of a diagonal and we must check
        for potential diagonal victories.  If it's odd, we can ignore diagonal checks 
        to save processing.  */
        if(_position % 2 == 0){
            return rowCheck(_index, _position, _checks, row, j) 
            || columnCheck(_index, _position, _checks, column, j) 
            || diagonalCheck(_index, _position);
        } else {
            return rowCheck(_index, _position, _checks, row, j) 
            || columnCheck(_index, _position, _checks, column, j);
        }
    }

    
    // Function to determine whether the game is at an impasse
    function checkTie (uint _index) internal view returns (bool){
        // Assumes the game is tied at the start of the function
        bool isTied = true;
        // Loops through each square on the board
        for (uint i = 0; i<9; i++){
            // If a square is unoccupied
            if(games[_index].boardData[i][0] == 0){
                // Change isTied to false and end the loop
                isTied = false;
                break;
            }
        }
        return isTied;
    }

    /*helper function to check if all three squares in the
    same row as the designated square have the same player
    mark*/
    function rowCheck (uint _index, uint _position, bool [3] memory _checks, int row, uint j) internal view returns (bool){
        for (int i = int(_position) - 2; i <= int(_position) + 2; i++){
            /*conditional checks to make sure the indices of the 
            examined squares are within bounds and in the same row 
            as the designated
            square*/
            if(i > 0 && i <= 8 && (i / 3 == row)){
                 _checks[j] = (games[_index].boardData[uint(i)][0] == games[_index].playerTurn);
                 j++;
            }
        }
        //resets the counter after the loop has completed
        j = 0;
        return (_checks[0] && _checks[1] && _checks[2]);
    }

    /*helper function to check if all three squares in the
    same column as the designated square have the same player
    mark*/
    function columnCheck (uint _index, uint _position, bool [3] memory _checks, int column, uint j) internal view returns (bool){
        for (int i = int(_position) - 3; i <= int(_position) + 3; i++){
            /*conditional checks to make sure the indices of the 
            examined squares are within bounds and in the same column 
            as the designated
            square*/
            if(i > 0 && i <= 8 && (i % 3 == column)){
                 _checks[j] = (games[_index].boardData[uint(i)][0] == games[_index].playerTurn);
                 j++;
            }
        }
        //resets the counter after the loop has completed
        j = 0;
        return (_checks[0] && _checks[1] && _checks[2]);
    }

     /*helper function to check if all three squares in the
    same diagonal as the designated square have the same player
    mark*/
    function diagonalCheck (uint _index, uint _position) internal view returns (bool){
        /*to save processing, we use a conditional to see which of
        two diagonals contains the specified square and only check
        the relevant diagonals*/
        if(_position == 0 || _position == 8){
            return diagonal1(_index);
        } else if (_position == 2 || _position == 6){
            return diagonal2(_index);
        } else {
            return diagonal1(_index) || diagonal2(_index);
        }
    }

    /*helper function to check if all three squares in the
    diagonal moving from the top left to bottom right of the
    the board have the same player mark*/
    function diagonal1(uint _index) internal view returns (bool){
        uint turn = games[_index].playerTurn;
        bool x = games[_index].boardData[0][0] == turn;
        bool y = games[_index].boardData[4][0] == turn;
        bool z = games[_index].boardData[8][0] == turn;
        return x && y && z;
    }

    /*helper function to check if all three squares in the
    diagonal moving from the top right to bottom left of the
    the board have the same player mark*/
    function diagonal2(uint _index) internal view returns (bool){
        uint turn = games[_index].playerTurn;
        bool x = games[_index].boardData[2][0] == turn;
        bool y = games[_index].boardData[4][0] == turn;
        bool z = games[_index].boardData[6][0] == turn;
        return x && y && z;
    }

    //helper function to return the absolute value of an integer
    function abs(int _integer) internal pure returns (uint){
        if(_integer >= 0){
            return uint(_integer);
        } else {
            return uint(-_integer);
        }
    }

    /*function used to calculate the adjacent and diagonal neighbors of a square
    by its index and return an array of neighboring squares*/
    function calculateNeighbors(uint _position) internal pure returns (uint[] memory){
        int row = int(_position / 3);
        int column = int(_position % 3);
        int8[8] memory neighborOffsets = [-4, -3, -2, -1, 1, 2, 3, 4];
        uint[8] memory _neighborsTemp;
        uint j = 0;

        for(uint i = 0; i <= 7; i++){
            int neighborPosition = int(_position) + neighborOffsets[i];
            int neighborRow = neighborPosition / 3;
            int neighborColumn = neighborPosition % 3;
            if ((int(0) <= neighborPosition && neighborPosition < int(9)) && ((abs(row - neighborRow) <= 1) && abs(column - neighborColumn) <= 1)){
               _neighborsTemp[j] = uint(neighborPosition);
               j++;
            }

        }

        uint[] memory _neighbors = new uint[](j);
        for(uint k = 0; k < j; k++){
            _neighbors[k] = _neighborsTemp[k];
        }
        return _neighbors;
    }

    /*If the play results in the victory condition being met,
    the game pot is added to the winning player's balance
    and the players' records are updated*/
    function resolveGame(uint _index, uint _playerTurn) internal {
        if(_playerTurn == 1){
            playerData[games[_index].player1].wins++;
            playerData[games[_index].player2].losses++;
            playerData[games[_index].player1].balanceOf += games[_index].gamePot;
            emit gameOver(_index, games[_index].gameID, games[_index].player1);
        } else if (_playerTurn == 2){
            playerData[games[_index].player2].wins++;
            playerData[games[_index].player1].losses++;
            playerData[games[_index].player2].balanceOf += games[_index].gamePot;
            emit gameOver(_index, games[_index].gameID, games[_index].player2);
        }
        games[_index].gamePot = 0;
        games[_index].playerTurn = 0;

    }

    //If tied, the pot is split evenly between the players and their records are updated.
    function resolveTie(uint _index) internal {
        playerData[games[_index].player1].ties++;
        playerData[games[_index].player1].balanceOf += (games[_index].gamePot / 2);
        playerData[games[_index].player2].ties++;
        playerData[games[_index].player2].balanceOf += (games[_index].gamePot / 2);
        games[_index].gamePot = 0;
        games[_index].playerTurn = 0;
        emit stalemate(_index, games[_index].gameID);
    }

    
    /* Function allowing any participating player to reign the game
    and forfeit the pot to the other player*/
    function resignGame(uint _index) public isPaused {
        address payable resignee = payable(msg.sender);
        address payable _player1 = games[_index].player1;
        address payable _player2 = games[_index].player2;
        // Requires that the function caller is one of the two players
        require(resignee == _player1 || resignee == _player2, "Unauthorized Address");
        if(resignee == _player1){
            playerData[_player2].balanceOf += games[_index].gamePot;
            playerData[_player2].wins++;
            playerData[_player1].resignations++;
        } else {
            playerData[_player1].balanceOf += games[_index].gamePot;
            playerData[_player1].wins++;
            playerData[_player2].resignations++;
        }
        games[_index].gamePot = 0;
        games[_index].playerTurn = 0;
        emit resignation(_index, games[_index].gameID, resignee);
    }

    //helper function to update the player turn at the end of each play
    function updatePlayerTurn(uint _index) internal {
        if (games[_index].playerTurn == 1){
            games[_index].playerTurn = 2;
            } 
        else if (games[_index].playerTurn == 2){
            games[_index].playerTurn = 1;
            }
    }

    function claimWinnings() public isPaused {
        uint _balance = playerData[msg.sender].balanceOf;
        transfer(payable(msg.sender), _balance);
    }

    function transfer(address payable _to, uint256 _amount) internal {
        (bool success,) = _to.call{value: _amount}("");
        emit withdrawInitiated(_to, _amount);
        require(success, "Failed to send Ether");
    }

    function claimFees() public onlyOwner{
        (bool success,) = msg.sender.call{value: ownerBalance}("");
        emit withdrawInitiated(msg.sender, ownerBalance);
        require(success, "Failed to send Ether");
    }

    function setFeePercentage(uint _newFeePercentage) public onlyOwner{
        feePercentage = _newFeePercentage;
    }

    function setTimeOutInterval(uint _newInterval) public onlyOwner{
        timeOutInterval = _newInterval;
    }

    function setPause(bool _newPauseState) public onlyOwner{
        pauseState = _newPauseState;
    }

    function getGameDataByIndex(uint _index) public view returns(Game memory){
        return games[_index];
    }


}
