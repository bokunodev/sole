# UID - Sortable, human friendly and lock free unique id library
1. 4 byte unix timstamp in seconds - with custom epoch
1. 4 byte counter - to make sure of uniqueness
1. 2 byte random - prevent user from accidentally typing other ppl ids

# Custom base32 charset with ambigues characters removed
Base32 charset: `0123456789ACDEFGHJKLMNPQRTUVWXYZ`

Ambigues characters
- `O -> 0`
- `I -> 1`
- `S -> 5`
- `B -> 8`

# Contribution:
Loop unrooling optimization for base32 encode and decode are inpired by [solutionroute/rid](https://github.com/solutionroute/rid)
