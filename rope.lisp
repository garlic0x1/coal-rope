(defpackage #:rope
  (:use #:coalton #:coalton-prelude)
  (:local-nicknames
   (#:string #:coalton-library/string)
   (#:list #:coalton-library/list)
   (#:math #:coalton-library/math)
   (#:iter #:coalton-library/iterator))
  (:shadow
   #:append)
  (:export
   #:Rope
   #:splice
   #:cut
   #:prepend
   #:append
   #:insert))
(in-package #:rope)
(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel

  ;;------------;;
  ;; Parameters ;;
  ;;------------;;

  (declare *short-leaf* UFix)
  (define *short-leaf* 16)

  (declare *long-leaf* UFix)
  (define *long-leaf* 16)

  ;;-------;;
  ;; Types ;;
  ;;-------;;

  (define-struct Dimensions
    (length UFix)
    (depth UFix))

  (define-type Rope
    (Branch Dimensions Rope Rope)
    (Leaf Dimensions String))

  ;;-------;;
  ;; Utils ;;
  ;;-------;;

  (declare rope-dimensions (Rope -> Dimensions))
  (define (rope-dimensions rope)
    (match rope
      ((Leaf dim _) dim)
      ((Branch dim _ _) dim)))

  (declare short-leaf? ((Into :a Rope) => Rope -> :a -> Boolean))
  (define (short-leaf? leaf obj)
    (match leaf
      ((Branch _ _ _) False)
      ((Leaf (Dimensions length _) _) 
       (>= *short-leaf* (+ length (.length (rope-dimensions (into obj))))))))

  (declare make-leaf (String -> Rope))
  (define (make-leaf str)
    (Leaf (Dimensions (into (string:length str)) 0) str))

  (declare collect (Rope -> (List String)))
  (define (collect rope)
    (match rope
      ((Leaf _ str) (make-list str))
      ((Branch _ l r) (list:append (collect l) (collect r)))))

  (declare weight (Rope -> UFix))
  (define (weight rope)
    (match rope
      ((Leaf (Dimensions length _) _) length)
      ((Branch _ l _) (.length (rope-dimensions l)))))

  ;;--------;;
  ;; Traits ;;
  ;;--------;;

  (define-instance (Into String Rope)
    (define (into str)
      (let length = (string:length str))
      (if (<= *long-leaf* length)
          (progn
            (let (Tuple ante post) = (string:split (math:div length 2) str))
            (splice (into ante) (into post)))
          (Leaf (Dimensions length 0) str))))

  (define-instance (Into Rope String)
    (define (into rope)
      (fold (fn (acc el) (string:concat acc el)) "" (collect rope))))

  ;;-----------;;
  ;; Rotations ;;
  ;;-----------;;

  (declare rotate-l (Rope -> Rope))
  (define (rotate-l rope)
    (match rope
      ((Leaf _ _) rope)
      ((Branch _ l (Branch _ rl rr)) (splice* (splice l rl) rr))
      ((Branch _ _ _) rope)))

  (declare rotate-r (Rope -> Rope))
  (define (rotate-r rope)
    (match rope
      ((Leaf _ _) rope)
      ((Branch _ (Branch _ ll lr) r) (splice* ll (splice lr r)))
      ((Branch _ _ _) rope)))

  (declare rotate-lr (Rope -> Rope))
  (define (rotate-lr rope)
    (match rope
      ((Leaf _ _) rope)
      ((Branch _ l r) (rotate-r (splice* (rotate-l l) r)))))

  (declare rotate-rl (Rope -> Rope))
  (define (rotate-rl rope)
    (match rope
      ((Leaf _ _) rope)
      ((Branch _ l r) (rotate-l (splice* l (rotate-r r))))))

  ;;-------------;;
  ;; AVL Balance ;;
  ;;-------------;;

  (declare balance-factor (Rope -> IFix))
  (define (balance-factor rope)
    (match rope
      ((Leaf _ _) 0)
      ((Branch _ l r)
       (- (into (.depth (rope-dimensions l)))
          (into (.depth (rope-dimensions r)))))))

  (declare balance (Rope -> Rope))
  (define (balance rope)
    (match rope
      ((Leaf _ _) rope)
      ((Branch _ l r)
       (let bf = (balance-factor rope))
       (cond ((< 1 bf)
              (balance
               (if (negative? (balance-factor l))
                   (rotate-lr rope)
                   (rotate-r rope))))
             ((> -1 bf)
              (balance
               (if (positive? (balance-factor r))
                   (rotate-rl rope)
                   (rotate-l rope))))
             (True rope)))))

  ;;-------------;;
  ;; Concatenate ;;
  ;;-------------;;

  (declare splice* (Rope -> Rope -> Rope))
  (define (splice* l r)
    (let (Dimensions length-l depth-l) = (rope-dimensions l))
    (let (Dimensions length-r depth-r) = (rope-dimensions r))
    (Branch (Dimensions (+ length-l length-r) (1+ (max depth-l depth-r)))
            l
            r))

  (declare splice (Rope -> Rope -> Rope))
  (define (splice l r)
    (balance (splice* l r)))

  ;;-------;;
  ;; Split ;;
  ;;-------;;

  (declare cut (Rope -> Ufix -> (Tuple Rope Rope)))
  (define (cut rope index)
    (match rope
      ((Leaf _ str)
       (let (Tuple ante post) = (string:split index str))
       (Tuple (make-leaf ante) (make-leaf post)))
      ((Branch _ l r)
       (let ((w (weight rope)))
         (cond ((== w index)
                (Tuple l r))
               ((< index w)
                (let (Tuple ante post) = (cut l index))
                (Tuple (balance ante) (splice post r)))
               ((> index w)
                (let (Tuple ante post) = (cut r (- index w)))
                (Tuple (splice l ante) (balance post))))))))

  ;;--------;;
  ;; Insert ;;
  ;;--------;;

  (declare prepend (Rope -> Rope -> Rope))
  (define (prepend rope obj)
    (match (Tuple rope obj)
      ((Tuple (Leaf _ str-a) (Leaf _ str-b))
       (if (short-leaf? rope obj)
           (make-leaf (string:concat str-b str-a))
           (splice obj rope)))
      ((Tuple _ (Branch _ _ _))
       (splice obj rope))
      ((Tuple (Branch _ l r) _)
       (splice (prepend l obj) r))))

  (declare append (Rope -> Rope -> Rope))
  (define (append rope obj)
    (match (Tuple rope obj)
      ((Tuple (Leaf _ str-a) (Leaf _ str-b))
       (if (short-leaf? rope obj)
           (make-leaf (string:concat str-a str-b))
           (splice rope obj)))
      ((Tuple _ (Branch _ _ _))
       (splice rope obj))
      ((Tuple (Branch _ l r) _)
       (splice l (append r obj)))))

  (declare insert ((Into :a Rope) => Rope -> UFix -> :a -> Rope))
  (define (insert rope index obj)
    (let (Tuple ante post) = (cut rope index))
    (splice (append ante (into obj)) post))

  ;;----------;;
  ;; Traverse ;;
  ;;----------;;

  (define-instance (iter:IntoIterator Rope Char)
    (define (iter:into-iter rope)
      (match rope
        ((Leaf _ str)
         (string:chars str))
        ((Branch _ l r)
         (iter:chain! (iter:into-iter l) (iter:into-iter r))))))
  )
