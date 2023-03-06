# UID - A human friendly unique id generator
1. 1 byte cluster id
1. 4 byte unix timstamp in seconds
1. 2 byte counter
1. 3 byte random

# Custom base32 charset with ambigues characters removed
Charset: `0123456789ABCDEFGHJKLMNPQRTVWXYZ`
Removed chars:
1. O -> 0
1. I -> 1
1. S -> 5
1. U -> V

Contribution:
Loop unrooling optimization for base32 encode and decode are inpired by [rid](https://github.com/solutionroute/rid)
