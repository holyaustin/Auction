
# Auction

## Introduction

A solidity smart contract for Auction

## Core Requirement

Core requirements of the contract (this is an auction contract):
● The admin can create the auction contract, and users can bid by locking tokens into
the contract.
● Users can lock incremental amounts of tokens to bid higher. For example, if a user
has already locked 100 tokens into the contract, and the user wants to bid higher to
120 tokens, then the user only needs to lock the increment amount of 20 tokens into
the contract (instead of locking 120 tokens).
● There’s a time limit for the auction. After the auction expires, the contract will no
longer accept new bids (or incremental bids).
● After the auction expires, the admin has up to 48 hours to choose the winner(s). If the
admin does not choose the winner(s) within 48 hours after contract expiry, the
contract will automatically choose the top N bidder(s) as the winner(s), with N being
the pre-defined number of winner(s).
● Non-selected bidder funds will be returned to the original bidding addresses
immediately after the winner(s) are chosen.
● After the transaction, the admin will confirm the deal per agreement with the auction
winner(s), and the locked funds will go to a designated address.

## Requirement for Additional features

Based on the core requirements above, conduct a code review on the deployed
contract and give constructive feedback on contract performance and security. (you
can use code screenshots for comment reference)
● Now we want a new feature that allows the bidders to “bid now and pay over time”.
The admin can set up an auction but only requires bidders to put down a down
payment for a portion of the deal. Once the deal is won by a bidder, only this bidder’s
wallet address is allowed to top up additional tokens in smart contracts for the
remainder of the deal. If the bidder decides to give up on paying for the remainder of
the deal, then a portion of the locked funds will be distributed to the admin as
compensation.
● Please propose the design for this new feature, including the core method design,
how to update the status of the smart contract, and how to sync with the web
platform (front-end and back-end). Please include relevant codes if needed.
