(load "mk/mk-vicare.scm")
(load "mk/mk.scm")
(load "mk/test-check.scm")

(set! allow-incomplete-search? #t)
(set! enable-conde1? #t)

(define closure-tag (gensym "#%closure"))
(define prim-tag (gensym "#%primitive"))

(define empty-env '())

;; TODO: specialized synthesis relational interpreter
;; specialized goal scheduling and eval continuation management
;; goal graph
;;   dependency ordered goal DAGs
;;     generate guesses for children first, whose results parents depend on
;;     generate guesses for most constrained/concrete goals first
;;       how is this measured and compared?
;;         maybe just consider topmost/head demanded terms for every demand path?
;;           propagate demand upward
;;             from results to terms, to results those terms require, etc.
;;           first satisfy each head independently
;;             to avoid wasting time in unsatisfiable problems
;;           then we can consider/generate heads in any order, updating as we go?
;;             need to re-evaluate/satisfy heads as constraints are added
;;             unbound logic variable listener map
;;               unbound variables -> affected goals
;;                 re-consider goals upon binding/constraining
;;     track relevance (terms are relevant if their results are demanded)
;;       procedure body that doesn't use an arg; only need to satisfy arg termination
;;       potentially 'satisfy-only' goals are put aside until demanded
;;         put aside with a satisfaction example in case it's difficult to compute?
;;           e.g., may be difficult to produce an 'absento' user gensym or shadowed prim
;;             note: need inductive proofs to terminate some unsatisfiable problems
;;   special constraints
;;     types and finite domains that don't require splitting states
;;       for simple values, closures and primitives
;;       also negated types and sets
;;     evaluated term map
;;       term -> (env -> result)
;;       i.e., unify results for same env
;;         term generators may use (env -> result) component to improve guesses
;;           e.g., `if` might partition results and satisfy partitions independently
;;           e.g., inductive proofs for terminating unsatisfiable problems
;;     term
;;     env
;;     operative
;;       term evaluating to a prim or lambda
;;       unshadowed syntactic symbol (e.g., quote, if, lambda, letrec, etc.)
;;     argument lists
;;       list-of-symbolso
;;       all different
;;       avoid shadowing
;;     negations?
;;       absento tags: closures, prims, user gensyms
;;       =/= for symbols during env lookup
;;       not-in-envo
;;       =/= for some evaluation results
;;         not #f (condition results and 'not' operator), not equal?, not null?
;;     there may be more...
;; grammar-based term recognizers and generators
;;   small, composable pieces to allow problems to be broken up and refined
;;   specialized unify/disunify predicates tied to boolean outcomes
;;     distinguish between test and assign
;; size incrementing generation
;; unshadowed environment enumeration
;; space and time quotas for evaluation slices
;; JIT denotational interpretation
;;   must continue to respect quotas
;;   escape when analysis is required (e.g., running into an unbound term)
;; strategic, benign incompleteness
;;   weighted disjunctions
;;   avoid redundant terms
;;     if both 'cons' and 'list' are available, usually no need to apply 'list'?
;;       but it may make sense to pass list as an argument
;;       and 'list' terms may be smaller and faster to find...
;;   limit generation of if/cond/match (can also do everything with just 'if')
;;   prefer applying primitives that produce booleans in conditional positions
;;   possibly omit applications of literal lambdas
;;   synthesize letrec rather than begin/define; can translate for the UI

(define (evalo expr val)
  (eval-expo expr initial-env val))

(define (eval-expo expr env val)
  (try-lookup-before expr env val (eval-expo-rest expr env val)))

(define (eval-expo-rest expr env val)
  (lambdag@ (st)
    (let* ((expr (walk expr (state-S st)))
           (env (walk env (state-S st)))
           (depth (state-depth st))
           (goal (lambdag@ (st)
                   ((conde
    ((numbero expr) (== expr val))

    ((fresh (rator rands prim-id)
       (== `(,rator . ,rands) expr)
       (eval-expo rator env `(,prim-tag . ,prim-id))
       (eval-primo prim-id val rands env)))

    ((fresh (rator x* rands body env^ a* res)
       (== `(,rator . ,rands) expr)
       ;; Multi-argument
       (eval-expo rator env `(,closure-tag (lambda ,x* ,body) ,env^))
       (ext-env*o x* a* env^ res)
       ; replacing eval-application with these may be faster with multi-level defer
       ;(eval-expo body res val)
       ;(eval-listo rands env a*)
       (eval-application rands env a* (eval-expo body res val))
       ))

    ((if-primo expr env val))

;    ((fresh (rator x rands body env^ a* res)
;       (== `(,rator . ,rands) expr)
;       ;; variadic
;       (symbolo x)
;       (== `((,x . (val . ,a*)) . ,env^) res)
;       (eval-expo rator env `(,closure-tag (lambda ,x ,body) ,env^))
;       (eval-expo body res val)
;       (eval-listo rands env a*)))

    ((== `(quote ,val) expr)
     (absento closure-tag val)
     (absento prim-tag val)
     (not-in-envo 'quote env))

    ((fresh (x body)
       (== `(lambda ,x ,body) expr)
       (== `(,closure-tag (lambda ,x ,body) ,env) val)
;       (conde$
;         ; Variadic
;         ((symbolo x))
;         ; Multiple argument
;         ((list-of-symbolso x)))
       (list-of-symbolso x)
       (not-in-envo 'lambda env)))

    ;; WEB 25 May 2016 -- This rather budget version of 'begin' is
    ;; useful for separating 'define' from the expression 'e',
    ;; specifically for purposes of Barliman.
    ((fresh (defn args name body e)
       (== `(begin ,defn ,e) expr)
       (== `(define ,name (lambda ,args ,body)) defn)
       (eval-expo `(letrec ((,name (lambda ,args ,body))) ,e) env val)))

    ((fresh (p-name x body letrec-body)
       ;; single-function variadic letrec version
       (== `(letrec ((,p-name (lambda ,x ,body)))
              ,letrec-body)
           expr)
;       (conde$
;         ; Variadic
;         ((symbolo x))
;         ; Multiple argument
;         ((list-of-symbolso x)))
       (list-of-symbolso x)
       (not-in-envo 'letrec env)
       (eval-expo letrec-body
                  `((,p-name . (rec . (lambda ,x ,body))) . ,env)
                  val)))

    ((prim-expo expr env val)))
                    (state-depth-set st depth)))))

      (if (or (var? expr)
              (var? env)
              (and (pair? expr) (var? (walk (car expr) (state-S st)))))
        (state-deferred-defer st goal)
        (goal st)))))

(define (lookupo x env t)
  (fresh (y b rest)
    (== `((,y . ,b) . ,rest) env)
    (conde;1 (((x x) (y y)))
      ((== x y)
       (conde;1 (((b b)))
         ((== `(val . ,t) b))
         ((fresh (lam-expr)
            (== `(rec . ,lam-expr) b)
            (== `(,closure-tag ,lam-expr ,env) t)))))
      ((=/= x y)
       (lookupo x rest t)))))

(define (try-lookup-before x env t alts)
  (lambdag@ (st)
    (let-values (((rgenv venv) (list-split-ground st env)))
      (let loop ((rgenv rgenv) (alts (conde$ ;1$ (((x x)))
                                       ((symbolo x) (lookupo x venv t))
                                       (alts))))
        (if (null? rgenv) (alts st)
          (let ((rib (car rgenv)))
            (loop (cdr rgenv)
              (fresh (y b)
                (== `(,y . ,b) rib)
                (conde$ ;1$ ((;(x x)
                           ;(y y)
                           ;))
                  ((symbolo x) (== x y)
                   (conde$ ;1$ (((b b)))
                     ((== `(val . ,t) b))
                     ((fresh (lam-expr)
                             (== `(rec . ,lam-expr) b)
                             (== `(,closure-tag ,lam-expr ,env) t)))))
                  ((=/= x y) alts))))))))))

(define (not-in-envo x env)
  (conde1 (((x x) (env env)))
    ((== empty-env env))
    ((fresh (y b rest)
       (== `((,y . ,b) . ,rest) env)
       (=/= y x)
       (not-in-envo x rest)))))

(define (eval-listo expr env val)
  (conde1 (((expr expr)) ((val val)))
    ((== '() expr)
     (== '() val))
    ((fresh (a d v-a v-d)
            (== `(,a . ,d) expr)
            (== `(,v-a . ,v-d) val)
            (eval-expo a env v-a)
            (eval-listo d env v-d)))))

(define (list-split-ground st xs)
  (let loop ((rprefix '()) (xs xs))
    (let ((tm (walk xs (state-S st))))
      (if (pair? tm)
        (loop (cons (walk (car tm) (state-S st)) rprefix) (cdr tm))
        (values rprefix xs)))))

(define (eval-application rands aenv a* body-goal)
  (define succeed unit)
  (lambdag@ (st)
    (let-values (((rrands rands-suffix) (list-split-ground st rands)))
      (let-values
        (((ggoals vgoals args-suffix)
          (let loop ((rands (reverse rrands))
                     (ggoals succeed)
                     (vgoals succeed)
                     (args a*))
            (if (null? rands) (values ggoals vgoals args)
              (let ((rand (car rands)))
                (let/vars st (args-rest)
                  (let ((goal (fresh (arg)
                                (== `(,arg . ,args-rest) args)
                                (eval-expo rand aenv arg))))
                    (if (var? rand)
                      (loop (cdr rands) ggoals (fresh () vgoals goal) args-rest)
                      (loop (cdr rands) (fresh () ggoals goal) vgoals args-rest)))))))))
        ((fresh ()
           ggoals    ; try ground arguments first
           body-goal ; then the body
           vgoals    ; then fill in unbound arguments
           ; any unbound final segment of arguments
           (eval-listo rands-suffix aenv args-suffix)) st)))))

;; need to make sure lambdas are well formed.
;; grammar constraints would be useful here!!!
(define (list-of-symbolso los)
  (conde1 (((los los)))
    ((== '() los))
    ((fresh (a d)
       (== `(,a . ,d) los)
       (symbolo a)
       (list-of-symbolso d)))))

(define (ext-env*o x* a* env out)
  (conde;1 (((x* x*)) ((a* a*)))
    ((== '() x*) (== '() a*) (== env out))
    ((fresh (x a dx* da* env2)
       (== `(,x . ,dx*) x*)
       (== `(,a . ,da*) a*)
       (== `((,x . (val . ,a)) . ,env) env2)
       (symbolo x)
       (ext-env*o dx* da* env2 out)))))

(define (eval-primo prim-id val rands env)
  (project0 (prim-id val rands env)
    (conde$ ;1$ (((prim-id prim-id)))
      [(== prim-id 'cons)
       (fresh (a d)
         (== `(,a . ,d) val)
         (eval-listo rands env `(,a ,d)))]
      [(== prim-id 'car)
       (fresh (d)
         (=/= closure-tag val)
         (eval-listo rands env `((,val . ,d))))]
      [(== prim-id 'cdr)
       (fresh (a)
         (=/= closure-tag a)
         (eval-listo rands env `((,a . ,val))))]
      [(== prim-id 'null?)
       (fresh (v)
         (let ((assign-result (conde$
                                ((== '() v) (== #t val))
                                ((=/= '() v) (== #f val))))
               (eval-args (eval-listo rands env `(,v))))
           (if (var? val)
             (fresh () eval-args assign-result)
             (fresh () assign-result eval-args))))]
      [(== prim-id 'pair?)
       (fresh (v)
         (let ((assign-true (fresh (a d) (== #t val) (== `(,a . ,d) v)))
               (assign-false (fresh () (== #f val) (conde$
                                                     ((== '() v))
                                                     ((symbolo v))
                                                     ((== #f v))
                                                     ((== #t v))
                                                     ((numbero v)))))
               (eval-args (eval-listo rands env `(,v))))
           (if (or (var? val) (eq? val #f))
             (fresh () eval-args (conde$ (assign-true) (assign-false)))
             (fresh () assign-true eval-args))))]
      [(== prim-id 'symbol?)
       (fresh (v)
         (let ((assign-true (fresh () (== #t val) (symbolo v)))
               (assign-false (fresh () (== #f val) (conde$
                                                     ((== '() v))
                                                     ((fresh (a d)
                                                        (== `(,a . ,d) v)))
                                                     ((== #f v))
                                                     ((== #t v))
                                                     ((numbero v)))))
               (eval-args (eval-listo rands env `(,v))))
           (if (or (var? val) (eq? val #f))
             (fresh () eval-args (conde$ (assign-true) (assign-false)))
             (fresh () assign-true eval-args))))]
      [(== prim-id 'not)
       (fresh (b)
         (let ((assign-result (conde$
                                ((== #f b) (== #t val))
                                ((=/= #f b) (== #f val))))
               (eval-args (eval-listo rands env `(,b))))
           (if (var? val)
             (fresh () eval-args assign-result)
             (fresh () assign-result eval-args))))]
      [(== prim-id 'equal?)
       (fresh (v1 v2)
         (let ((assign-result (conde$
                                ((== v1 v2) (== #t val))
                                ((=/= v1 v2) (== #f val))))
               (eval-args (eval-listo rands env `(,v1 ,v2))))
           (if (var? val)
             (fresh () eval-args assign-result)
             (fresh () assign-result eval-args))))]
      [(== prim-id 'list)
       (eval-listo rands env val)])))

(define (prim-expo expr env val)
  (conde1$ (((expr expr)))
    ((boolean-primo expr env val))
    ))

(define (boolean-primo expr env val)
  (conde1$ (((expr expr)) ((val val)))
    ((== #t expr) (== #t val))
    ((== #f expr) (== #f val))))

;; Set this flag to #f to recover Scheme semantics.
(define boolean-conditions-only? #t)
(define (condition v)
  (if (and allow-incomplete-search? boolean-conditions-only?)
    (booleano v)
    unit))
(define (condition-true v)
  (if (and allow-incomplete-search? boolean-conditions-only?)
    (== #t v)
    (=/= #f v)))

(define (if-primo expr env val)
  (fresh (e1 e2 e3 t)
    (== `(if ,e1 ,e2 ,e3) expr)
    (not-in-envo 'if env)
    (eval-expo e1 env t)
    (conde1 (((t t)))
      ((condition-true t) (eval-expo e2 env val))
      ((== #f t) (eval-expo e3 env val)))))

(define initial-env `((cons . (val . (,prim-tag . cons)))
                      (car . (val . (,prim-tag . car)))
                      (cdr . (val . (,prim-tag . cdr)))
                      (null? . (val . (,prim-tag . null?)))
                      (pair? . (val . (,prim-tag . pair?)))
                      (symbol? . (val . (,prim-tag . symbol?)))
                      (not . (val . (,prim-tag . not)))
                      (equal? . (val . (,prim-tag . equal?)))
                      (list . (val . (,prim-tag . list)))
                      ;(list . (val . (,closure-tag (lambda x x) ,empty-env)))
                      . ,empty-env))

(define (booleano t)
  (conde1$ (((t t)))
    ((== #f t))
    ((== #t t))))


;; Tests

(time (test 'list-nth-element-peano
  (run 1 (q r)
    (evalo `(begin
              (define nth
                (lambda (n xs)
                  (if (null? n) ,q ,r)))
              (list
                (nth '() '(foo bar))
                (nth '(s) '(foo bar))
                (nth '() '(1 2 3))
                (nth '(s) '(1 2 3))
                (nth '(s s) '(1 2 3))))
           (list 'foo 'bar 1 2 3)))
  '((((car xs) (nth (cdr n) (cdr xs)))))))

(time
 (test 'map-hard-0-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (== `(define map
                (lambda (f xs)
                  (if (null? xs)
                    xs (cons (f (car xs)) (map f (cdr xs))))))
             defn)
         (evalo `(begin
                   ,defn
                   (list
                     (map ',g1 '())
                     (map car '((,g2 . ,g3)))
                     (map cdr '((,g4 . ,g5) (,g6 . ,g7)))))
                (list '() `(,g2) `(,g5 ,g7))))))
   '(((define map
        (lambda (f xs)
          (if (null? xs)
            xs (cons (f (car xs)) (map f (cdr xs))))))))))

(time
 (test 'map-hard-1-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh (a b c)
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (== `(define map
                (lambda (f xs)
                  (if (null? xs)
                    ,a (cons ,b (map f ,c)))))
           defn)
         (evalo `(begin
                   ,defn
                   (list
                     (map ',g1 '())
                     (map car '((,g2 . ,g3)))
                     (map cdr '((,g4 . ,g5) (,g6 . ,g7)))))
                (list '() `(,g2) `(,g5 ,g7))))))
   '(((define map
        (lambda (f xs)
          (if (null? xs)
            xs (cons (f (car xs)) (map f (cdr xs))))))))))

(time
 (test 'map-hard-2-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh (a)
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (== `(define map
                (lambda (f xs)
                  (if (null? xs)
                    xs (cons (f (car xs)) (map ,a (cdr xs))))))
             defn)
         (evalo `(begin
                   ,defn
                   (list
                     (map ',g1 '())
                     (map car '((,g2 . ,g3)))
                     (map cdr '((,g4 . ,g5) (,g6 . ,g7)))))
                (list '() `(,g2) `(,g5 ,g7))))))
   '(((define map
        (lambda (f xs)
          (if (null? xs)
            xs (cons (f (car xs)) (map f (cdr xs))))))))))

;(time
 ;(test 'map-hard-3-gensym
   ;(run 1 (defn)
     ;(let ((g1 (gensym "g1"))
           ;(g2 (gensym "g2"))
           ;(g3 (gensym "g3"))
           ;(g4 (gensym "g4"))
           ;(g5 (gensym "g5"))
           ;(g6 (gensym "g6"))
           ;(g7 (gensym "g7")))
       ;(fresh (a)
         ;(absento g1 defn)
         ;(absento g2 defn)
         ;(absento g3 defn)
         ;(absento g4 defn)
         ;(absento g5 defn)
         ;(absento g6 defn)
         ;(absento g7 defn)
         ;(== `(define map
                ;(lambda (f xs) ,a))
             ;defn)
         ;(evalo `(begin
                   ;,defn
                   ;(list
                     ;(map ',g1 '())
                     ;(map car '((,g2 . ,g3)))
                     ;(map cdr '((,g4 . ,g5) (,g6 . ,g7)))))
                ;(list '() `(,g2) `(,g5 ,g7))))))
   ;'(((define map
        ;(lambda (f xs)
          ;(if (null? xs)
            ;xs (cons (f (car xs)) (map f (cdr xs))))))))))

;(time
 ;(test 'map-hard-4-gensym
   ;(run 1 (defn)
     ;(let ((g1 (gensym "g1"))
           ;(g2 (gensym "g2"))
           ;(g3 (gensym "g3"))
           ;(g4 (gensym "g4"))
           ;(g5 (gensym "g5"))
           ;(g6 (gensym "g6"))
           ;(g7 (gensym "g7")))
       ;(fresh ()
         ;(absento g1 defn)
         ;(absento g2 defn)
         ;(absento g3 defn)
         ;(absento g4 defn)
         ;(absento g5 defn)
         ;(absento g6 defn)
         ;(absento g7 defn)
         ;(evalo `(begin
                   ;,defn
                   ;(list
                     ;(map ',g1 '())
                     ;(map car '((,g2 . ,g3)))
                     ;(map cdr '((,g4 . ,g5) (,g6 . ,g7)))))
                ;(list '() `(,g2) `(,g5 ,g7))))))
   ;'(((define map
        ;(lambda (_.0 _.1)
          ;(if (null? _.1)
            ;_.1 (cons (_.0 (car _.1)) (map _.0 (cdr _.1))))))
      ;(sym _.0 _.1)))))

(test 'append-empty
  (run 1 (q)
       (evalo
         `(begin
            (define append
              (lambda (l s)
                (if (null? l)
                  s
                  (cons (car l)
                        (append (cdr l) s)))))
            (append '() '()))
         '()))
  '((_.0)))

(test 'append-all-answers
  (run* (l1 l2)
        (evalo `(begin
                  (define append
                    (lambda (l s)
                      (if (null? l)
                        s
                        (cons (car l)
                              (append (cdr l) s)))))
                  (append ',l1 ',l2))
               '(1 2 3 4 5)))
  '(((() (1 2 3 4 5)))
    (((1) (2 3 4 5)))
    (((1 2) (3 4 5)))
    (((1 2 3) (4 5)))
    (((1 2 3 4) (5)))
    (((1 2 3 4 5) ()))))

;;; flipping rand/body eval order makes this one too hard,
;;; but dynamic ordering via eval-application fixes it!
(test 'append-cons-first-arg
  (run 1 (q)
    (evalo `(begin (define append
                     (lambda (l s)
                       (if (null? l)
                         s
                         (cons ,q
                               (append (cdr l) s)))))
                   (append '(1 2 3) '(4 5)))
           '(1 2 3 4 5)))
  '(((car l))))

(test 'append-cdr-arg
  (run 1 (q)
       (evalo `(begin
                 (define append
                   (lambda (l s)
                     (if (null? l)
                       s
                       (cons (car l)
                             (append (cdr ,q) s)))))
                 (append '(1 2 3) '(4 5)))
              '(1 2 3 4 5)))
  '((l)))

(test 'append-cdr
  (run 1 (q)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l)
                          (append (,q l) s)))))
              (append '(1 2 3) '(4 5)))
           '(1 2 3 4 5)))
  '((cdr)))

(time (test 'append-hard-1
  (run 1 (q r)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l)
                          (append (,q ,r) s)))))
              (append '(1 2 3) '(4 5)))
           '(1 2 3 4 5)))
  '(((cdr l)))))

(time (test 'append-hard-2
  (run 1 (q)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l)
                          (append ,q s)))))
              (append '(1 2 3) '(4 5)))
           '(1 2 3 4 5)))
  '(((cdr l)))))

(time (test 'append-hard-3
  (run 1 (q r)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l)
                          (append ,q ,r)))))
              (list
                (append '(foo) '(bar))
                (append '(1 2 3) '(4 5))))
           (list '(foo bar) '(1 2 3 4 5))))
  '((((cdr l) s)))))

(time (test 'append-hard-4
  (run 1 (q)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l)
                          (append . ,q)))))
              (list
                (append '(foo) '(bar))
                (append '(1 2 3) '(4 5))))
           (list '(foo bar) '(1 2 3 4 5))))
  '((((cdr l) s)))))

(time (test 'append-hard-5
  (run 1 (q r)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons ,q
                          (append . ,r)))))
              (list
                (append '() '())
                (append '(foo) '(bar))
                (append '(1 2 3) '(4 5))))
           (list '() '(foo bar) '(1 2 3 4 5))))
  '((((car l) ((cdr l) s))))))

;; the following are still overfitting
;; probably need to demote quote and some others

(time
 (test 'append-hard-6-gensym-dummy-test
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q a b)

           (== `(append ,a ,b) q)

           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        s
                        (cons (car l) ,q))))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(printf "append-hard-6-gensym-less-dummy-test takes ~~16s\n")
(time
 (test 'append-hard-6-gensym-less-dummy-test
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q a b c)

           (== `(,a ,b ,c) q)

           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        s
                        (cons (car l) ,q))))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(printf "append-hard-6-no-gensym returns an over-specific, incorrect answer\n")
(time (test 'append-hard-6-no-gensym
  (run 1 (q)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons (car l) ,q))))
              (list
                (append '() '())
                (append '(foo) '(bar))
                (append '(1 2 3) '(4 5))))
           (list '() '(foo bar) '(1 2 3 4 5))))
  '(((append (cdr l) s)))))

(time
 (test 'append-hard-6-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q)
           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        s
                        (cons (car l) ,q))))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
 (test 'append-hard-7-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q r)
           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        s
                        (cons ,q ,r))))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(test 'append-hard-7-no-gensym
  (run 1 (q r)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l)
                    s
                    (cons ,q ,r))))
              (list
                (append '() '())
                (append '(foo) '(bar))
                (append '(1 2 3) '(4 5))))
           (list '() '(foo bar) '(1 2 3 4 5))))
  '((((car l) (append (cdr l) s)))))

(time
 (test 'append-hard-8-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q)
           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        s
                        ,q)))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
 (test 'append-hard-9-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q r)
           (== `(define append
                  (lambda (l s)
                    (if (null? l)
                        ,q
                        ,r)))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
 (test 'append-hard-10-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q r s)
           (== `(define append
                  (lambda (l s)
                    (if (null? ,q)
                        ,r
                        ,s)))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
 (test 'append-hard-11-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q r s t)
           (== `(define append
                  (lambda (l s)
                    (if (,t ,q)
                        ,r
                        ,s)))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
  (test 'append-equal-0
        (run 1 (defn)
          (let ((g1 (gensym "g1"))
                (g2 (gensym "g2"))
                (g3 (gensym "g3"))
                (g4 (gensym "g4"))
                (g5 (gensym "g5"))
                (g6 (gensym "g6"))
                (g7 (gensym "g7")))
            (fresh ()
              (absento g1 defn)
              (absento g2 defn)
              (absento g3 defn)
              (absento g4 defn)
              (absento g5 defn)
              (absento g6 defn)
              (absento g7 defn)
              (evalo `(begin
                        ,defn
                        (list
                          (equal? '() (append '() '()))
                          (equal? (list ',g1 ',g2) (append '(,g1) '(,g2)))
                          (equal? (list ',g3 ',g4 ',g5 ',g6) (append '(,g3 ,g4) '(,g5 ,g6)))))
                     (list #t #t #t)))))
        '(((define append
             (lambda (_.0 _.1)
               (if (null? _.0)
                 _.1
                 (cons (car _.0) (append (cdr _.0) _.1)))))
           (sym _.0 _.1)))))

(time
  (test 'append-equal-1
        (run 1 (defn)
          (let ((g1 (gensym "g1"))
                (g2 (gensym "g2"))
                (g3 (gensym "g3"))
                (g4 (gensym "g4"))
                (g5 (gensym "g5"))
                (g6 (gensym "g6"))
                (g7 (gensym "g7")))
            (fresh ()
              (absento g1 defn)
              (absento g2 defn)
              (absento g3 defn)
              (absento g4 defn)
              (absento g5 defn)
              (absento g6 defn)
              (absento g7 defn)
              (evalo `(begin
                        ,defn
                        (list
                          (equal? (append '() '()) '())
                          (equal? (append '(,g1) '(,g2)) (list ',g1 ',g2))
                          (equal? (append '(,g3 ,g4) '(,g5 ,g6)) (list ',g3 ',g4 ',g5 ',g6))))
                     (list #t #t #t)))))
        '(((define append
             (lambda (_.0 _.1)
               (if (null? _.0)
                 _.1
                 (cons (car _.0) (append (cdr _.0) _.1)))))
           (sym _.0 _.1)))))

(time
  (test 'interp-0
    (run 1 (defn)
      (let ((g1 (gensym "g1"))
            (g2 (gensym "g2"))
            (g3 (gensym "g3"))
            (g4 (gensym "g4"))
            (g5 (gensym "g5"))
            (g6 (gensym "g6"))
            (g7 (gensym "g7")))
        (fresh (a b c d)
          (absento g1 defn)
          (absento g2 defn)
          (absento g3 defn)
          (absento g4 defn)
          (absento g5 defn)
          (absento g6 defn)
          (absento g7 defn)
          (== `(define eval-expr
                 (lambda (expr env)
                   (match expr
                     [`(quote ,datum) datum]
                     [`(lambda (,(? symbol? x)) ,body)
                       (lambda (a)
                         (eval-expr body (lambda (y)
                                           (if (equal? ,a ,b)
                                             ,c
                                             (env ,d)))))]
                     [(? symbol? x) (env x)]
                     [`(cons ,e1 ,e2) (cons (eval-expr e1 env) (eval-expr e2 env))]
                     [`(,rator ,rand) ((eval-expr rator env) (eval-expr rand env))])))
              defn)
          (evalo `(begin
                    ,defn
                    (list
                      (eval-expr '((lambda (y) y) ',g1) 'initial-env)
                      (eval-expr '(((lambda (z) z) (lambda (v) v)) ',g2) 'initial-env)
                      (eval-expr '(((lambda (a) (a a)) (lambda (b) b)) ',g3) 'initial-env)
                      (eval-expr '(((lambda (c) (lambda (d) c)) ',g4) ',g5) 'initial-env)
                      (eval-expr '(((lambda (f) (lambda (v1) (f (f v1)))) (lambda (e) e)) ',g6) 'initial-env)
                      (eval-expr '((lambda (g) ((g g) g)) (lambda (i) (lambda (j) ',g7))) 'initial-env)
                      ))
                 (list
                   g1
                   g2
                   g3
                   g4
                   g6
                   g7
                   )))))
    '(((define eval-expr
         (lambda (expr env)
           (match expr
             [`(quote ,datum) datum]
             [`(lambda (,(? symbol? x)) ,body)
               (lambda (a)
                 (eval-expr body (lambda (y)
                                   (if (equal? y x)
                                     a
                                     (env y)))))]
             [(? symbol? x) (env x)]
             [`(cons ,e1 ,e2) (cons (eval-expr e1 env) (eval-expr e2 env))]
             [`(,rator ,rand) ((eval-expr rator env) (eval-expr rand env))])))))))

;(time
  ;(test 'interp-1
    ;(run 1 (defn)
      ;(let ((g1 (gensym "g1"))
            ;(g2 (gensym "g2"))
            ;(g3 (gensym "g3"))
            ;(g4 (gensym "g4"))
            ;(g5 (gensym "g5"))
            ;(g6 (gensym "g6"))
            ;(g7 (gensym "g7")))
        ;(fresh (a b c d)
          ;(absento g1 defn)
          ;(absento g2 defn)
          ;(absento g3 defn)
          ;(absento g4 defn)
          ;(absento g5 defn)
          ;(absento g6 defn)
          ;(absento g7 defn)
          ;(== `(define eval-expr
                 ;(lambda (expr env)
                   ;(match expr
                     ;[`(quote ,datum) datum]
                     ;[`(lambda (,(? symbol? x)) ,body)
                       ;(lambda (a)
                         ;(eval-expr body (lambda (y)
                                           ;(if (equal? ,a ,b)
                                             ;,c
                                             ;,d))))]
                     ;[(? symbol? x) (env x)]
                     ;[`(cons ,e1 ,e2) (cons (eval-expr e1 env) (eval-expr e2 env))]
                     ;[`(,rator ,rand) ((eval-expr rator env) (eval-expr rand env))])))
              ;defn)
          ;(evalo `(begin
                    ;,defn
                    ;(list
                      ;(eval-expr '((lambda (y) y) ',g1) 'initial-env)
                      ;(eval-expr '(((lambda (z) z) (lambda (v) v)) ',g2) 'initial-env)
                      ;(eval-expr '(((lambda (a) (a a)) (lambda (b) b)) ',g3) 'initial-env)
                      ;(eval-expr '(((lambda (c) (lambda (d) c)) ',g4) ',g5) 'initial-env)
                      ;(eval-expr '(((lambda (f) (lambda (v1) (f (f v1)))) (lambda (e) e)) ',g6) 'initial-env)
                      ;(eval-expr '((lambda (g) ((g g) g)) (lambda (i) (lambda (j) ',g7))) 'initial-env)
                      ;))
                 ;(list
                   ;g1
                   ;g2
                   ;g3
                   ;g4
                   ;g6
                   ;g7
                   ;)))))
    ;'(((define eval-expr
         ;(lambda (expr env)
           ;(match expr
             ;[`(quote ,datum) datum]
             ;[`(lambda (,(? symbol? x)) ,body)
               ;(lambda (a)
                 ;(eval-expr body (lambda (y)
                                   ;(if (equal? y x)
                                     ;a
                                     ;(env y)))))]
             ;[(? symbol? x) (env x)]
             ;[`(cons ,e1 ,e2) (cons (eval-expr e1 env) (eval-expr e2 env))]
             ;[`(,rator ,rand) ((eval-expr rator env) (eval-expr rand env))])))))))

(time
 (test 'append-hard-12-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q r s)
           (== `(define append
                  (lambda (l s)
                    (if ,q
                        ,r
                        ,s)))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

(time
 (test 'append-hard-13-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (fresh (q)
           (== `(define append
                  (lambda (l s) ,q))
               defn)
           (evalo `(begin
                     ,defn
                     (list
                      (append '() '())
                      (append '(,g1) '(,g2))
                      (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   '(((define append (lambda (l s) (if (null? l) s (cons (car l) (append (cdr l) s)))))))))

; append-hard-15-gensym seems just as good, so don't waste time on this test case by default
;(time
 ;(test 'append-hard-14-gensym
   ;(run 1 (defn)
     ;(let ((g1 (gensym "g1"))
           ;(g2 (gensym "g2"))
           ;(g3 (gensym "g3"))
           ;(g4 (gensym "g4"))
           ;(g5 (gensym "g5"))
           ;(g6 (gensym "g6"))
           ;(g7 (gensym "g7")))
       ;(fresh ()
         ;(absento g1 defn)
         ;(absento g2 defn)
         ;(absento g3 defn)
         ;(absento g4 defn)
         ;(absento g5 defn)
         ;(absento g6 defn)
         ;(absento g7 defn)
         ;(fresh (p q r)
           ;(== `(define ,p
                  ;(lambda ,q ,r))
               ;defn)
           ;(evalo `(begin
                     ;,defn
                     ;(list
                      ;(append '() '())
                      ;(append '(,g1) '(,g2))
                      ;(append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                  ;(list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7)))))))
   ;'(((define append (lambda (_.0 _.1) (if (null? _.0) _.1 (cons (car _.0) (append (cdr _.0) _.1))))) (sym _.0 _.1)))))

; this one seems just as fast as append-hard-14-gensym
(time
 (test 'append-hard-15-gensym
   (run 1 (defn)
     (let ((g1 (gensym "g1"))
           (g2 (gensym "g2"))
           (g3 (gensym "g3"))
           (g4 (gensym "g4"))
           (g5 (gensym "g5"))
           (g6 (gensym "g6"))
           (g7 (gensym "g7")))
       (fresh ()
         (absento g1 defn)
         (absento g2 defn)
         (absento g3 defn)
         (absento g4 defn)
         (absento g5 defn)
         (absento g6 defn)
         (absento g7 defn)
         (evalo `(begin
                   ,defn
                   (list
                     (append '() '())
                     (append '(,g1) '(,g2))
                     (append '(,g3 ,g4 ,g5) '(,g6 ,g7))))
                (list '() `(,g1 ,g2) `(,g3 ,g4 ,g5 ,g6 ,g7))))))
   '(((define append
        (lambda (_.0 _.1)
          (if (null? _.0)
            _.1
            (cons (car _.0)
                  (append (cdr _.0) _.1)))))
      (sym _.0 _.1)))))

(time (test 'reverse-1
  (run 1 (q r s)
    (evalo `(begin
              (define append
                (lambda (l s)
                  (if (null? l) s
                    (cons (car l)
                          (append (cdr l) s)))))
              (begin
                (define reverse
                  (lambda (xs)
                    (if (null? xs) '()
                      (,q (reverse ,r) ,s))))
                (list
                  (reverse '())
                  (reverse '(a))
                  (reverse '(foo bar))
                  (reverse '(1 2 3)))))
          (list '() '(a) '(bar foo) '(3 2 1))))
  '(((append (cdr xs) (list (car xs)))))))

(time (test 'reverse-2
  (run 1 (defn)
    (let ((g1 (gensym "g1"))
          (g2 (gensym "g2"))
          (g3 (gensym "g3"))
          (g4 (gensym "g4"))
          (g5 (gensym "g5"))
          (g6 (gensym "g6"))
          (g7 (gensym "g7")))
      (fresh (q r s)
        (absento g1 defn)
        (absento g2 defn)
        (absento g3 defn)
        (absento g4 defn)
        (absento g5 defn)
        (absento g6 defn)
        (absento g7 defn)
        (== `(define reverse
               (lambda (xs)
                 (if (null? xs)
                   '()
                   (,q (reverse ,r) ,s))))
            defn)
        (evalo `(begin
                  (define append
                    (lambda (l s)
                      (if (null? l) s
                        (cons (car l)
                              (append (cdr l) s)))))
                  (begin
                    ,defn
                    (list
                      (reverse '())
                      (reverse '(,g1))
                      (reverse '(,g2 ,g3))
                      (reverse '(,g4 ,g5 ,g6)))))
               (list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  '(((define reverse
       (lambda (xs)
         (if (null? xs)
           '()
           (append (reverse (cdr xs))
                   (list (car xs))))))))))

;(time (test 'reverse-3
  ;(run 1 (defn)
    ;(let ((g1 (gensym "g1"))
          ;(g2 (gensym "g2"))
          ;(g3 (gensym "g3"))
          ;(g4 (gensym "g4"))
          ;(g5 (gensym "g5"))
          ;(g6 (gensym "g6"))
          ;(g7 (gensym "g7")))
      ;(fresh (q r s)
        ;(absento g1 defn)
        ;(absento g2 defn)
        ;(absento g3 defn)
        ;(absento g4 defn)
        ;(absento g5 defn)
        ;(absento g6 defn)
        ;(absento g7 defn)
        ;(== `(define reverse
               ;(lambda (xs)
                 ;(if (null? xs)
                   ;'()
                   ;(append (,q ,r) ,s))))
            ;defn)
        ;(evalo `(begin
                  ;(define append
                    ;(lambda (l s)
                      ;(if (null? l) s
                        ;(cons (car l)
                              ;(append (cdr l) s)))))
                  ;(begin
                    ;,defn
                    ;(list
                      ;(reverse '())
                      ;(reverse '(,g1))
                      ;(reverse '(,g2 ,g3))
                      ;(reverse '(,g4 ,g5 ,g6)))))
               ;(list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  ;'(((define reverse
       ;(lambda (xs)
         ;(if (null? xs)
           ;'()
           ;(append (reverse (cdr xs))
                   ;(list (car xs))))))))))

;(time (test 'reverse-4
  ;(run 1 (defn)
    ;(let ((g1 (gensym "g1"))
          ;(g2 (gensym "g2"))
          ;(g3 (gensym "g3"))
          ;(g4 (gensym "g4"))
          ;(g5 (gensym "g5"))
          ;(g6 (gensym "g6"))
          ;(g7 (gensym "g7")))
      ;(fresh (q r)
        ;(absento g1 defn)
        ;(absento g2 defn)
        ;(absento g3 defn)
        ;(absento g4 defn)
        ;(absento g5 defn)
        ;(absento g6 defn)
        ;(absento g7 defn)
        ;(== `(define reverse
               ;(lambda (xs)
                 ;(if (null? xs)
                   ;'()
                   ;(append ,q ,r))))
            ;defn)
        ;(evalo `(begin
                  ;(define append
                    ;(lambda (l s)
                      ;(if (null? l) s
                        ;(cons (car l)
                              ;(append (cdr l) s)))))
                  ;(begin
                    ;,defn
                    ;(list
                      ;(reverse '())
                      ;(reverse '(,g1))
                      ;(reverse '(,g2 ,g3))
                      ;(reverse '(,g4 ,g5 ,g6)))))
               ;(list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  ;'(((define reverse
       ;(lambda (xs)
         ;(if (null? xs)
           ;'()
           ;(append (reverse (cdr xs))
                   ;(list (car xs))))))))))

;(time (test 'reverse-5
  ;(run 1 (defn)
    ;(let ((g1 (gensym "g1"))
          ;(g2 (gensym "g2"))
          ;(g3 (gensym "g3"))
          ;(g4 (gensym "g4"))
          ;(g5 (gensym "g5"))
          ;(g6 (gensym "g6"))
          ;(g7 (gensym "g7")))
      ;(fresh (q)
        ;(absento g1 defn)
        ;(absento g2 defn)
        ;(absento g3 defn)
        ;(absento g4 defn)
        ;(absento g5 defn)
        ;(absento g6 defn)
        ;(absento g7 defn)
        ;(absento 'match defn)
        ;(== `(define reverse
               ;(lambda (xs)
                 ;(if (null? xs)
                   ;'()
                   ;,q)))
            ;defn)
        ;(evalo `(begin
                  ;(define append
                    ;(lambda (l s)
                      ;(if (null? l) s
                        ;(cons (car l)
                              ;(append (cdr l) s)))))
                  ;(begin
                    ;,defn
                    ;(list
                      ;(reverse '())
                      ;(reverse '(,g1))
                      ;(reverse '(,g2 ,g3))
                      ;(reverse '(,g4 ,g5 ,g6)))
                    ;)
                  ;)
               ;(list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  ;'(((define reverse
       ;(lambda (xs)
         ;(if (null? xs)
           ;'()
           ;(append (reverse (cdr xs))
                   ;(list (car xs))))))))))

;(time (test 'reverse-6
  ;(run 1 (defn)
    ;(let ((g1 (gensym "g1"))
          ;(g2 (gensym "g2"))
          ;(g3 (gensym "g3"))
          ;(g4 (gensym "g4"))
          ;(g5 (gensym "g5"))
          ;(g6 (gensym "g6"))
          ;(g7 (gensym "g7")))
      ;(fresh (q r s)
        ;(absento g1 defn)
        ;(absento g2 defn)
        ;(absento g3 defn)
        ;(absento g4 defn)
        ;(absento g5 defn)
        ;(absento g6 defn)
        ;(absento g7 defn)
        ;(== `(define reverse
               ;(lambda (xs)
                 ;(if ,q ,r ,s)))
            ;defn)
        ;(evalo `(begin
                  ;(define foldl
                    ;(lambda (f acc xs)
                      ;(if (null? xs)
                        ;acc
                        ;(foldl f (f (car xs) acc) (cdr xs)))))
                  ;(begin
                    ;,defn
                    ;(list
                      ;(reverse '())
                      ;(reverse '(,g1))
                      ;(reverse '(,g2 ,g3))
                      ;(reverse '(,g4 ,g5 ,g6)))))
               ;(list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  ;'(((define reverse
       ;(lambda (xs)
         ;(if (null? xs)
           ;xs
           ;(foldl cons '() xs))))))))

(time (test 'reverse-7
  (run 1 (defn)
    (let ((g1 (gensym "g1"))
          (g2 (gensym "g2"))
          (g3 (gensym "g3"))
          (g4 (gensym "g4"))
          (g5 (gensym "g5"))
          (g6 (gensym "g6"))
          (g7 (gensym "g7")))
      (fresh (q r s)
        (absento g1 defn)
        (absento g2 defn)
        (absento g3 defn)
        (absento g4 defn)
        (absento g5 defn)
        (absento g6 defn)
        (absento g7 defn)
        (== `(define reverse
               (lambda (xs) ,q))
            defn)
        (evalo `(begin
                  (define foldl
                    (lambda (f acc xs)
                      (if (null? xs)
                        acc
                        (foldl f (f (car xs) acc) (cdr xs)))))
                  (begin
                    ,defn
                    (list
                      (reverse '())
                      (reverse '(,g1))
                      (reverse '(,g2 ,g3))
                      (reverse '(,g4 ,g5 ,g6)))))
               (list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  '(((define reverse
       (lambda (xs)
         (if (null? xs)
           xs
           (foldl cons '() xs))))))))

;(time (test 'reverse-8
  ;(run 1 (defn)
    ;(let ((g1 (gensym "g1"))
          ;(g2 (gensym "g2"))
          ;(g3 (gensym "g3"))
          ;(g4 (gensym "g4"))
          ;(g5 (gensym "g5"))
          ;(g6 (gensym "g6"))
          ;(g7 (gensym "g7")))
      ;(fresh ()
        ;(absento g1 defn)
        ;(absento g2 defn)
        ;(absento g3 defn)
        ;(absento g4 defn)
        ;(absento g5 defn)
        ;(absento g6 defn)
        ;(absento g7 defn)
        ;(evalo `(begin
                  ;(define foldl
                    ;(lambda (f acc xs)
                      ;(if (null? xs)
                        ;acc
                        ;(foldl f (f (car xs) acc) (cdr xs)))))
                  ;(begin
                    ;,defn
                    ;(list
                      ;(reverse '())
                      ;(reverse '(,g1))
                      ;(reverse '(,g2 ,g3))
                      ;(reverse '(,g4 ,g5 ,g6)))))
               ;(list '() `(,g1) `(,g3 ,g2) `(,g6 ,g5 ,g4))))))
  ;'(((define reverse
       ;(lambda (xs)
         ;(if (null? xs)
           ;xs
           ;(foldl cons '() xs))))))))

(time (test 'rev-tailcall-1
  (run 1 (defn)
    (let ((g1 (gensym "g1"))
          (g2 (gensym "g2"))
          (g3 (gensym "g3"))
          (g4 (gensym "g4"))
          (g5 (gensym "g5"))
          (g6 (gensym "g6"))
          (g7 (gensym "g7")))
      (fresh (q r s)
        (absento g1 defn)
        (absento g2 defn)
        (absento g3 defn)
        (absento g4 defn)
        (absento g5 defn)
        (absento g6 defn)
        (absento g7 defn)
        (evalo `(begin
                  ,defn
                  (list
                    (rev-tailcall '() ',g7)
                    (rev-tailcall '(,g1) ',g7)
                    (rev-tailcall '(,g2 ,g3) ',g7)
                    (rev-tailcall '(,g4 ,g5 ,g6) ',g7)))
               (list g7 `(,g1 . ,g7) `(,g3 ,g2 . ,g7) `(,g6 ,g5 ,g4 . ,g7))))))
  '(((define rev-tailcall
       (lambda (_.0 _.1)
         (if (null? _.0)
           _.1
           (rev-tailcall (cdr _.0) (cons (car _.0) _.1)))))
     (sym _.0 _.1)))))
