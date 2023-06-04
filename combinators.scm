;; === UNDER HEAVY CONSTRUCTION ===

(library (combinators)
         ;; === building blocks ===
         (export parse-string
                 monad-do
                 return
                 bind
                 zero
                 fmap
                 satisfy
                 ;; === choices ===
                 or-else
                 try
                 choice
                 option
                 ignore
                 left
                 right
                 between
                 ;; === sequences ===
                 and-then
                 sequence
                 many
                 many-1
                 skip-many
                 sep-by
                 sep-by-1
                 end-by
                 end-by-1
                 count)
         (import (rnrs base)
                 (rnrs lists)
                 (rnrs unicode)
                 (data)
                 (utils))

         ;; === BASE ===

         ;; Applies a parser to a string and outputs a parsing context.
         (define parse-string
           (lambda (parser text)
             (let-values ([(reply state output) (parser (make-state (string->list text) 1 0))])
               (list reply state output))))

         ;; === MONAD ===

         ;; The Haskell "do" syntax (simplified). Makes monads readable.
         ;; Renamed "monad-do" because "do" is less descriptive.
         (define-syntax monad-do
           (syntax-rules (<-)
             [(_ expression) expression]
             [(_ (x <- mx) expression ...)
              (bind mx (lambda (x) 
                         (monad-do expression ...)))]))

         ;; Wraps a value within a parser.
         (define return
           (lambda (x)
             (lambda (state)
               (values EMPTY-OK state x))))

         ;; Also named ">>=".
         ;; The binding operation benefits combinator parsing twofold:
         ;; 1. Integrates the sequencing of parsers with the processing of their results.
         ;; 2. Makes the context of previous parsers available to subsequent parsers.
         ;;
         ;; Input Consumption of (>>=) for Parsers "p" and "q".
         ;; Side-Note: essentially behaves like Boolean "or".
         ;;
         ;; | p        | q        | (p >>= q) |
         ;; | -------- | -------- | --------- |
         ;; | Empty    | Empty    | Empty     |
         ;; | Empty    | Consumed | Consumed  |
         ;; | Consumed | Empty    | Consumed  |
         ;; | Consumed | Consumed | Consumed  |
         (define bind
           (lambda (px f)
             (lambda (state)
               (let-values ([(reply-x state-x output-x) (px state)])
                 (cond
                   [(equal? reply-x EMPTY-OK)    ((f output-x) state-x)]
                   [(equal? reply-x EMPTY-ERROR) (values reply-x state-x output-x)]
                   [(equal? reply-x CONSUMED-OK) (let-values ([(reply-y state-y output-y) ((f output-x) state-x)])
                                                   (values (cons CONSUMED (cdr reply-y)) state-y output-y))]
                   [else (values reply-x state-x output-x)])))))

         ;; Sets parser context to empty.
         (define zero
           (lambda (state)
             (values EMPTY-ERROR state '())))

         ;; === functor ===

         ;; Reaches inside a parser and transforms its output with an arbitrary function.
         (define fmap
           (lambda (f px)
             (monad-do (x <- px)
                       (return (f x)))))

         ;; === satisfy ===

         ;; Provides a parser that only consumes its input if that input satisfies the
         ;; provided predicate.
         (define satisfy
           (lambda (test)
             (lambda (state)
               (let ([input  (state-input  state)]
                     [line   (state-line   state)]
                     [column (state-column state)])
                 (if (empty? input)
                     (values EMPTY-ERROR state '())
                     (let ([x  (car input)]
                           [xs (cdr input)])
                       (if (test x)
                           (values CONSUMED-OK
                                   ;; Although #\linefeed and #\newline are synonymous
                                   ;; older Schemes recognize only #\newline
                                   (if (or (char=? x #\linefeed) (char=? x #\newline))
                                       (make-state xs (+ line 1) 0)
                                       (make-state xs line (+ column 1)))
                                   x)
                           (values EMPTY-ERROR state '()))))))))

         ;; === choice ===
         ;; side-note: beware of space leaks.

         ;; Applies parser "px" to the input. If "px" succeeds, parser "py" is ignored.
         ;; If "px" fails, "py" is applied to the same input and its result is outputted
         ;; regardless od whether it succeeds or fails.
         ;; To prevent space leaks, "or-else" ignores parser "py" if parser "px" consumes
         ;; any input prior to failing. This behavior can be inverted with the
         ;; "try" combinator.
         (define or-else
           (lambda (px py)
             (lambda (state)
               (let-values ([(reply-x state-x output-x) (px state)])
                 (cond
                   [(equal? reply-x EMPTY-ERROR) (py state)]
                   [(equal? reply-x EMPTY-OK)    (let-values ([(reply-y state-y output-y) (py state)])
                                                   (if (eq? (car reply-y) EMPTY)
                                                       (values EMPTY-OK state-y output-y)
                                                       (values reply-y  state-y output-y)))]
                   [else (values reply-x state-x output-x)])))))


         ;; === try: LL(∞) ===

         ;; Parser "(try px)" behaves exactly like parser "px" except
         ;; that it pretends it hasn't consumed any input if "px" fails.
         ;; This allows combinator "or-else" unlimited lookahead.
         (define try
           (lambda (px)
             (lambda (state)
               (let-values ([(reply-x state-x output-x) (px state)])
                 (if (equal? reply-x CONSUMED-ERROR)
                     (values EMPTY-ERROR state-x output-x)
                     (values reply-x     state-x output-x))))))

         ;; Applies each parser in a list, outputting the result of the first successful parser.
         ;; Also named "asum" within the context of Alternatives.
         ;; Also named "msum" within the context of Monads.
         (define choice
           (lambda (parsers)
             (fold-right or-else zero parsers)))

         ;; Applies parser px. If px fails, outputs the value y.
         (define option
           (lambda (px y)
             (or-else px (return y))))

         ;; Applies parser px. If px succeeds, ignores its result and outputs y.
         (define ignore
           (lambda (px y)
             (monad-do (x <- px)
                       (return y))))

         ;; Also named ".>>", "left" parses two values and discards the right.
         (define left
           (lambda (px py)
             (monad-do (x <- px)
                       (y <- py)
                       (return x))))

         ;; Also named ">>.", "right" parses two values and discards the left.
         (define right
           (lambda (px py)
             (monad-do (x <- px)
                       (y <- py)
                       (return y))))

         ;; Parses three values, and, if successful, discards the left and the right values.
         (define between
           (lambda (px py pz)
             (monad-do (x <- px)
                       (y <- py)
                       (z <- pz)
                       (return y))))

         ;; === sequence ===

         ;; Applies parsers "px" and "py", only outputting a pair of values if both parsers succeed.
         (define and-then
           (lambda (px py)
             (monad-do (x <- px)
                       (y <- py)
                       (return (cons x y)))))

         ;; Applies a list of parsers, only outputting a list of values if all parsers succeed.
         (define sequence
           (lambda (parsers)
             (fold-right and-then (return '()) parsers)))

         ;; Applies a parser zero or more times. Outputs a list of zero or more parsed values.
         (define many
           (lambda (px)
             (or-else (many-1 px)
                      (return '()))))

         ;; Applies a parser one or more times. Only outputs a list of one or more parsed values.
         (define many-1
           (lambda (px)
             (monad-do (x  <- px)
                       (xs <- (many px))
                       (return (cons x xs)))))
         
         ;; (define skip-many
         ;;   (lambda (px)
         ;;     (ignore (many px) '())))

         ;; Applies a parser zero or more times, ignoring the result.
         (define skip-many
           (lambda (px)
             (define scan
               (lambda ()
                 (or-else (monad-do (x <- px) (scan))
                          (return '()))))
             (scan)))

         ;; Parses zero or more occurrences of parser "px" separated by parser "sep".
         ;; Outputs a list of zero or more parsed values.
         (define sep-by
           (lambda (px sep)
             (or-else (sep-by-1 px sep)
                      (return '()))))

         ;; Parses one or more occurrences of parser "px" separated by parser "sep".
         ;; Only outputs a list of one or more parsed values.
         (define sep-by-1
           (lambda (px sep)
             (monad-do (x  <- px)
                       (xs <- (many (monad-do (s <- sep)
                                              (y <- px)
                                              (return y))))
                       (return (cons x xs)))))

         ;; Parses zero or more occurrences of parser "px" separated and ended by parser "sep".
         ;; Outputs a list of zero or more parsed values.
         (define end-by
           (lambda (px sep)
             (many (monad-do (x <- px)
                             (s <- sep)
                             (return x)))))

         ;; Parses one or more occurrences of parser "px" separated and ended by parser "sep".
         ;; Only outputs a list of one or more parsed values.
         (define end-by-1
           (lambda (px sep)
             (many-1 (monad-do (x <- px)
                               (s <- sep)
                               (return x)))))

         ;; Applies parser "n" number of times. Outputs a list of parsed values.
         ;; If "n" is less than or equal to zero, the parser outputs an empty list for all inputs.
         (define count
           (lambda (n px)
             (if (<= n 0)
                 (return '())
                 (sequence (repeat n px)))))
         
         )
