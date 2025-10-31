# glep: grep utility in Gleam

## Background

I started this project as part of the CodeCrafters
["Build your own grep"](https://app.codecrafters.io/courses/grep/overview)
challenge.

I went down a bit of a rabbit hole and learned about the
[Brzozowski derivative](https://en.wikipedia.org/wiki/Brzozowski_derivative) on
strings in formal language theory, which can be used to implement regular
expression matching.

A paper by Owens, Reppy and Turon [^1] provides an overview of the theory with
some direction on how to implement regex matching using derivatives. It mentions
the use of this technique in `ml-ulex` [^2], a lexer generator for Standard ML.
I translated some of the SML/NJ code in `ml-ulex`, relating to the regex smart
constructor functions, into Gleam as the paper did not describe the details of
the ordering relation used to reduce expressions into a canonical form during
construction.

[^1]: Owens, Reppy, and Turon:
[Regular-expression derivatives reexamined](https://www.khoury.northeastern.edu/home/turon/re-deriv.pdf).

[^2]: [`ml-ulex`](https://github.com/smlnj/smlnj/tree/5b49ebb10b8f61093c3ed48dec30cd3bca173b89/tools/ml-lpt/ml-ulex)
in the SML/NJ Github repo
