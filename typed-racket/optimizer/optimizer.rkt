#lang racket/base

(require syntax/parse syntax/stx unstable/sequence
         racket/pretty
         (for-template racket/base)
         "../utils/utils.rkt"
         (private syntax-properties)
         (optimizer utils logging
                    number fixnum float float-complex vector string list pair
                    sequence box struct dead-code apply unboxed-let
                    hidden-costs))

(provide optimize-top)



(define-syntax-class opt-expr
  #:commit
  #:literal-sets (kernel-literals)
  #:attributes (opt)
  (pattern opt:expr
    #:when (or (ignore-property #'opt)
               (ignore-some-property #'opt)
               (with-handlers-property #'opt)))
  
  ;; can't optimize the body of this code because it isn't typechecked
  (pattern ((~and op (~literal let-values))
            ([(i:id) e-rhs:expr]) e-body:expr ...)
           #:when (kw-lambda-property this-syntax)
           #:with opt-rhs ((optimize) #'e-rhs)
           #:with opt (quasisyntax/loc/origin this-syntax #'op
                        (op ([(i) opt-rhs]) e-body ...)))

  ;; interesting cases, where something is optimized
  (pattern e:dead-code-opt-expr       #:with opt #'e.opt)
  (pattern e:unboxed-let-opt-expr     #:with opt #'e.opt)
  (pattern e:apply-opt-expr           #:with opt #'e.opt)
  (pattern e:number-opt-expr          #:with opt #'e.opt)
  (pattern e:fixnum-opt-expr          #:with opt #'e.opt)
  (pattern e:float-opt-expr           #:with opt #'e.opt)
  (pattern e:float-complex-opt-expr   #:with opt #'e.opt)
  (pattern e:vector-opt-expr          #:with opt #'e.opt)
  (pattern e:string-opt-expr          #:with opt #'e.opt)
  (pattern e:list-opt-expr            #:with opt #'e.opt)
  (pattern e:pair-opt-expr            #:with opt #'e.opt)
  (pattern e:sequence-opt-expr        #:with opt #'e.opt)
  (pattern e:box-opt-expr             #:with opt #'e.opt)
  (pattern e:struct-opt-expr          #:with opt #'e.opt)
  (pattern e:hidden-cost-log-expr     #:with opt #'e.opt)

  ;; boring cases, just recur down
  (pattern ((~and op (~or (~literal #%plain-lambda) (~literal define-values)))
            formals e:expr ...)
           #:with opt (quasisyntax/loc/origin this-syntax #'op (op formals #,@(stx-map (optimize) #'(e ...)))))
  (pattern ((~and op case-lambda) [formals e:expr ...] ...)
           ;; optimize all the bodies
           #:with (opt-parts ...)
           (for/list ([part (in-syntax #'([formals e ...] ...))])
             (let ((l (syntax->list part)))
               (cons (car l)
                     (map (optimize) (cdr l)))))
           #:with opt (syntax/loc/origin this-syntax #'op (op opt-parts ...)))  
  (pattern ((~and op (~or (~literal let-values) (~literal letrec-values)))
            ([ids e-rhs:expr] ...) e-body:expr ...)
           #:with (opt-rhs ...) (stx-map (optimize) #'(e-rhs ...))
           #:with opt (quasisyntax/loc/origin this-syntax #'op
                        (op ([ids opt-rhs] ...)
                            #,@(stx-map (optimize) #'(e-body ...)))))
  (pattern ((~and op letrec-syntaxes+values) stx-bindings
                                             ([(ids ...) e-rhs:expr] ...)
                                             e-body:expr ...)
           ;; optimize all the rhss
           #:with (opt-clauses ...)
           (for/list ([clause (in-syntax #'([(ids ...) e-rhs] ...))])
             (let ((l (syntax->list clause)))
               (list (car l) ((optimize) (cadr l)))))
           #:with opt (quasisyntax/loc/origin this-syntax #'op
                        (letrec-syntaxes+values
                         stx-bindings
                         (opt-clauses ...)
                         #,@(stx-map (optimize) #'(e-body ...)))))
  (pattern (kw:identifier expr ...)
           #:when
	   (for/or ([k (in-list (list #'if #'begin #'begin0 #'set! #'#%plain-app #'#%app #'#%expression
			                      #'#%variable-reference #'with-continuation-mark))])
	     (free-identifier=? k #'kw))
           ;; we don't want to optimize in the cases that don't match the #:when clause
           #:with opt (quasisyntax/loc/origin this-syntax #'kw
                        (kw #,@(stx-map (optimize) #'(expr ...)))))
  (pattern other:expr
           #:with opt #'other))

(define (optimize-top stx)
  (parameterize ([optimize (syntax-parser [e:opt-expr #'e.opt])])
    (let ((result ((optimize) stx)))
      (when *show-optimized-code*
        (pretty-print (syntax->datum result)))
      result)))
