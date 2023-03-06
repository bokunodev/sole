# UID - A human friendly unique id generator
1. 1 byte cluster id - consistence across clusters or threads
1. 4 byte unix timstamp in seconds - 4,294,967,295 max ids (uint32) with custom epoch
1. 2 byte counter - to make sure of uniqueness
1. 3 byte random - to prevent user from accidentally typing other ppl ids

# Custom base32 charset with ambigues characters removed
Base32 charset: `0123456789ABCDEFGHJKLMNPQRTVWXYZ`

Removed chars:
1. `O -> 0`
1. `I -> 1`
1. `S -> 5`
1. `U -> V`

Contribution:

Loop unrooling optimization for base32 encode and decode are inpired by [rid](https://github.com/solutionroute/rid)
