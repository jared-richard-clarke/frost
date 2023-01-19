(import (rnrs))

;; === UNDER HEAVY CONSTRUCTION ===

;; A parser combinator library is a functional approach to building recursive descent parsers.
;; Basic functions implement parsers, whereas higher-order functions (combinators) implement
;; grammar constructions such as choice, sequencing, and repetition.
;;
;; (parser (list char)) -> (list) | (list any (list char))

;; === utils ===

(define empty? null?)

;; === base ===

(define item
  (lambda (x)
    (if (empty? x)
        x
        (list (car x) (cdr x)))))

;; === monad ====

;; Also named "unit".
(define return
  (lambda (x)
    (lambda (input)
      (list x input))))

;; Also named ">>=".
;; Integrates the sequencing of parsers with the processing of their results.
(define bind
  (lambda (px f)
    (lambda (input)
      (let ([x (px input)])
        (if (empty? x)
            x
            ((f (car x)) (cadr x)))))))

;; Also named "empty".
(define zero
  (lambda ()
    (lambda input '())))

;; === functor ===

(define map-f
  (lambda (f px)
    (bind px (lambda (x)
               (return (f x))))))

;; === applicative ===

(define apply-p
  (lambda (px py)
    (bind px (lambda (x)
               (map-f x py)))))

;; (define apply-p
;;   (lambda (px py)
;;     (bind px (lambda (x)
;;                (bind py (lambda (y)
;;                           (return (x y))))))))

;; === satisfy ===

(define satisfy
  (lambda (predicate)
    (bind item (lambda (x)
                 (if (predicate x)
                     (return x)
                     (zero))))))

;; === choices ===

(define or-else
  (lambda (px py)
    (lambda (input)
      (let ([x (px input)])
        (if (empty? x)
            (py input)
            x)))))

(define choice
  (lambda (parsers)
    (fold-left or-else (car parsers) (cdr parsers))))

;; === sequences ===

(define and-then
  (lambda (px py)
    (bind px (lambda (x)
               (bind py (lambda (y)
                          (return (cons x y))))))))

(define sequence
  (lambda (parsers)
    (fold-right and-then (return '()) parsers)))

;; === parsers ===

(define parse-char
  (lambda (x)
    (satisfy (lambda (y) (char=? x y)))))

(define parse-digit 
  (satisfy char-numeric?))

(define parse-letter
  (satisfy char-alphabetic?))

(define parse-space 
  (satisfy char-whitespace?))
