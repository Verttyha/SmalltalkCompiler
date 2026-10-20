%token IDENTIFIER KEYWORD BINARY_SELECTOR
%token SELF SUPER TRUE_VALUE FALSE_VALUE NIL_VALUE
%token INTEGER FLOAT_VALUE SCALED_DECIMAL CHAR_VALUE STRING_VALUE
%token SYMBOL SELECTOR

%token MINUS "-" BAR "|"
%token ASSIGN ":=" RETURN "^"
%token LPAREN "(" RPAREN ")"
%token LBRACKET "[" RBRACKET "]"
%token LBRACE "{" RBRACE "}"
%token HASH "#" COLON ":" PERIOD "." SEMICOLON ";" CHUNK_END "!"
%token SCOPE_SEPARATOR

%start program

%%

/* ============================================================
   Программа и последовательность выражений
   ============================================================ */

program:                  // Программа
    definitions body chunk_end                      // Пример: Object subclass: Person [] Person new!
;

definitions:              // Объявления
    %empty                                          // Пример: 1 + 2
  | definitions class_definition                    // Пример: Object subclass: Person []
  | definitions class_extension                     // Пример: Person extend [ size [ ^1 ] ]
  | definitions eval_block                          // Пример: Eval [ 1 + 2 ]
;

chunk_end:                // Конец фрагмента программы
    %empty                                          // Пример: 1 + 2
  | "!"                                             // Пример: 1 + 2!
;

body:                     // Тело
    temporaries statements                          // Пример: | x | x := 1. x printNl
;

temporaries:              // Временные переменные
    %empty                                          // Пример: self size
  | "|" identifiers "|"                             // Пример: | x result |
;

identifiers:              // Идентификаторы
    %empty                                          // Пример: | |
  | identifiers IDENTIFIER                          // Пример: x result
;

statements:               // Последовательность выражений
    %empty                                          // Пример: []
  | expression statement_tail                       // Пример: x := 1. x printNl
  | "^" expression optional_period                  // Пример: ^self.
;

statement_tail:           // Продолжение последовательности
    %empty                                          // Пример: x := 1
  | "." statements                                 // Пример: x := 1. x printNl
;

optional_period:          // Необязательная точка
    %empty                                          // Пример: ^self
  | "."                                            // Пример: ^self.
;

expression:               // Выражение
    message_expression                              // Пример: self size
  | IDENTIFIER ":=" expression                      // Пример: a := b := 10
;

/* ============================================================
   Сообщения: unary, binary, keyword и каскады
   ============================================================ */

message_expression:       // Выражение с отправкой сообщений
    primary                                         // Пример: 42
  | message_send cascades                           // Пример: Transcript show: 'hello'; cr
;

message_send:             // Отправка сообщения
    unary_message                                   // Пример: items size
  | binary_message                                  // Пример: 1 + 2
  | keyword_message                                 // Пример: items at: 1
;

unary_expression:         // Выражение с унарными сообщениями
    primary                                         // Пример: items
  | unary_message                                   // Пример: items size
;

unary_message:            // Унарное сообщение
    unary_expression IDENTIFIER                     // Пример: object class name
;

binary_expression:        // Выражение с бинарными сообщениями
    unary_expression                                // Пример: items size
  | binary_message                                  // Пример: 1 + 2 * 3
;

binary_message:           // Бинарное сообщение
    binary_expression binary_selector unary_expression // Пример: 1 + items size
;

keyword_message:          // Сообщение с ключевыми словами
    binary_expression keyword_parts                 // Пример: items at: 1 put: 2 + 3
;

keyword_parts:            // Части сообщения с ключевыми словами
    KEYWORD binary_expression                       // Пример: at: 1
  | keyword_parts KEYWORD binary_expression          // Пример: at: 1 put: 2
;

binary_selector:          // Бинарный селектор
    BINARY_SELECTOR                                 // Пример: 1 + 2
  | "-"                                             // Пример: 5 - 2
  | "|"                                             // Пример: true | false
;

cascades:                 // Каскад сообщений
    %empty                                          // Пример: Transcript cr
  | cascades ";" cascade_message                    // Пример: Transcript cr; show: 'hello'; cr
;

cascade_message:          // Сообщение в каскаде
    IDENTIFIER                                      // Пример: Transcript show: 'hello'; cr
  | binary_selector unary_expression                // Пример: 1 + 2; + 1
  | keyword_parts                                   // Пример: Transcript cr; show: 'hello'
;

/* ============================================================
   Значения, блоки и массивы
   ============================================================ */

primary:                  // Первичное выражение
    qualified_name                                  // Пример: Smalltalk.Array
  | SELF                                            // Пример: self
  | SUPER                                           // Пример: super initialize
  | literal                                         // Пример: 42
  | block                                           // Пример: [ :x | x + 1 ]
  | "(" expression ")"                             // Пример: (1 + 2)
  | dynamic_array                                   // Пример: { 1 + 2. object size }
;

qualified_name:           // Имя с пространством имён
    IDENTIFIER                                      // Пример: Person
  | qualified_name SCOPE_SEPARATOR IDENTIFIER        // Пример: Smalltalk.Array
;

literal:                  // Литерал
    number                                          // Пример: 42
  | "-" number                                      // Пример: -42
  | CHAR_VALUE                                      // Пример: $A
  | STRING_VALUE                                    // Пример: 'hello'
  | SYMBOL                                          // Пример: #'hello world'
  | SELECTOR                                        // Пример: #at:put:
  | TRUE_VALUE                                      // Пример: true
  | FALSE_VALUE                                     // Пример: false
  | NIL_VALUE                                       // Пример: nil
  | literal_array                                   // Пример: #(1 2 3)
;

number:                   // Число
    INTEGER                                         // Пример: 42
  | FLOAT_VALUE                                     // Пример: 1.5
  | SCALED_DECIMAL                                  // Пример: 1.25s2
;

block:                    // Блок
    "[" block_arguments body "]"                    // Пример: [ :x :y | | result | result := x + y. result ]
;

block_arguments:          // Объявление параметров блока
    %empty                                          // Пример: [ self size ]
  | block_parameters "|"                            // Пример: [ :x :y | x + y ]
;

block_parameters:         // Список параметров блока
    ":" IDENTIFIER                                  // Пример: :x
  | block_parameters ":" IDENTIFIER                 // Пример: :x :y
;

literal_array:            // Литеральный массив
    "#" "(" literal_elements ")"                    // Пример: #(1 'text' name (2 3))
;

literal_elements:         // Элементы литерального массива
    %empty                                          // Пример: #()
  | literal_elements literal_element                // Пример: #(1 'text' name)
;

literal_element:          // Элемент литерального массива
    literal                                         // Пример: #(42 'text')
  | IDENTIFIER                                      // Пример: #(name)
  | KEYWORD                                         // Пример: #(at:)
  | binary_selector                                 // Пример: #(+)
  | "(" literal_elements ")"                        // Пример: #(1 (2 3))
;

dynamic_array:            // Массив из выражений
    "{" array_values "}"                            // Пример: { 1 + 2. object size }
;

array_values:             // Содержимое массива
    %empty                                          // Пример: {}
  | expression_list optional_period                 // Пример: { 1 + 2. object size. }
;

expression_list:          // Список выражений
    expression                                      // Пример: 1 + 2
  | expression_list "." expression                  // Пример: 1 + 2. object size
;

/* ============================================================
   Классы и методы Smalltalk
   ============================================================ */

class_definition:         // Объявление класса
    qualified_name KEYWORD IDENTIFIER "[" class_body "]" // Пример: Object subclass: Person [ | name | ]
;

class_extension:          // Расширение класса
    qualified_name IDENTIFIER "[" class_body "]"     // Пример: Person extend [ name [ ^name ] ]
  | qualified_name IDENTIFIER IDENTIFIER "[" class_body "]" // Пример: Person class extend [ answer [ ^42 ] ]
;

class_body:               // Тело класса
    temporaries class_members                       // Пример: | name | name [ ^name ]
;

class_members:            // Члены класса
    %empty                                          // Пример: Object subclass: Person []
  | class_members method_definition                 // Пример: name [ ^name ]
  | class_members IDENTIFIER ":=" expression "."    // Пример: Count := 0.
;

method_definition:        // Объявление метода
    method_pattern "[" body "]"                     // Пример: size [ ^1 ]
  | qualified_name IDENTIFIER BINARY_SELECTOR method_pattern "[" body "]" // Пример: Person class >> new [ ^super new ]
;

method_pattern:           // Селектор и параметры метода
    IDENTIFIER                                      // Пример: size
  | binary_selector IDENTIFIER                      // Пример: + other
  | keyword_parameters                              // Пример: at: index put: value
;

keyword_parameters:       // Ключевые слова и параметры метода
    KEYWORD IDENTIFIER                              // Пример: at: index
  | keyword_parameters KEYWORD IDENTIFIER            // Пример: at: index put: value
;

eval_block:               // Блок выполнения
    IDENTIFIER "[" body "]"                          // Пример: Eval [ Transcript show: 'hello'; cr ]
;

%%
