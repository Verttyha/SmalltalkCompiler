%option noyywrap never-interactive
%option noinput nounput nodefault nounistd 8bit

%{
    #include "Buffer.h"
    // потом в console h
    #include <iomanip>
    #include <iostream>
    #include <limits>

    inline const char* TokenName(TokenKind type) {
        static const char* const names[] = {
            "IDENTIFIER", "KEYWORD", "BINARY_SELECTOR", "MINUS", "BAR",
            "SELF", "SUPER", "TRUE", "FALSE", "NIL", "INTEGER", "FLOAT",
            "SCALED_DECIMAL", "CHARACTER", "STRING", "SYMBOL_LITERAL", "SELECTOR_LITERAL",
            "ASSIGN", "RETURN", "LPAREN", "RPAREN", "LBRACKET", "RBRACKET",
            "HASH", "COLON", "PERIOD", "SEMICOLON", "CHUNK_END", "LBRACE", "RBRACE", "SCOPE_SEPARATOR", "ERROR"
        };
        static_assert(sizeof(names) / sizeof(names[0]) == LEX_ERROR - IDENTIFIER + 1);
        return names[type - IDENTIFIER];
    }

    // Оформление вывода токенов и сообщений об ошибках.
    class Console {
    public:
        static void Log(const Token& token) {
            std::cout << std::setprecision(std::numeric_limits<double>::max_digits10)
                      << token.start.line << ':' << token.start.column
                      << "  " << TokenName(token.type) << "  value=";

            switch (token.type) {
            case IDENTIFIER: case KEYWORD: case BINARY_SELECTOR: case MINUS: case BAR:
            case STRING_VALUE: case SYMBOL: case SELECTOR:
                PrintString(std::get<std::string>(token.value));
                break;

            case LEX_ERROR:
                PrintString(std::get<std::string>(token.value));
                std::cout << " lexeme=";
                PrintString(token.lexeme);
                break;

            case CHAR_VALUE: {
                unsigned code = static_cast<unsigned char>(std::get<char>(token.value));
                std::cout << code << " (U+" << std::hex << std::uppercase << code
                          << std::dec << std::nouppercase << ')';
                break;
            }

            case INTEGER:
                std::cout << std::get<IntegerValue>(token.value);
                break;

            case FLOAT_VALUE:
                std::cout << std::get<double>(token.value);
                break;

            case SCALED_DECIMAL:
                std::cout << std::get<DecimalValue>(token.value).value;
                break;

            case TRUE_VALUE: case FALSE_VALUE:
                std::cout << (std::get<bool>(token.value) ? "true" : "false");
                break;

            default:
                std::cout << '-';
            }

            if (!token.details.empty()) std::cout << " (" << token.details << ')';
            std::cout << '\n';
        }

        static void Error(const std::string& message) {
            std::cerr << message << '\n';
        }

        static void Summary(std::size_t tokens, std::size_t errors) {
            std::cout << tokens << " tokens, " << errors << " lexical errors\n";
        }

    private:
        // Видимое оформление LF/TAB/backslash в логе. Значение токена не изменяется.
        static void PrintString(const std::string& text) {
            std::cout << '"';
            for (unsigned char c : text) {
                if (c == '\n')      std::cout << "\\n";
                else if (c == '\r') std::cout << "\\r";
                else if (c == '\t') std::cout << "\\t";
                else if (c == '\\' || c == '"') std::cout << '\\' << char(c);
                else if (c < 32 || c >= 127) {
                    std::cout << "\\x" << std::hex << std::setw(2) << std::setfill('0')
                              << unsigned(c) << std::dec << std::setfill(' ');
                } else {
                    std::cout << char(c);
                }
            }
            std::cout << '"';
        }
    };

    #include <cstdio>

    using namespace std;

    Buffer buffer;
    Token currentToken{};
    TokenKind stringKind = STRING_VALUE;
    size_t tokenCount = 0, errorCount = 0;

    int emit(TokenKind type, TokenValue value = {}, const string& details = "") {
        currentToken = {type, value, details, buffer.lexeme, buffer.tokenStart, buffer.position};
        Console::Log(currentToken);

        if (type == LEX_ERROR) ++errorCount;
        else                  ++tokenCount;

        return type;
    }

    int error(const string& message) {
        return emit(LEX_ERROR, message);
    }

    int identifier(const string& text) {
        if (text == "self")  return emit(SELF);
        if (text == "super") return emit(SUPER);
        if (text == "nil")   return emit(NIL_VALUE);
        if (text == "true")  return emit(TRUE_VALUE, true);
        if (text == "false") return emit(FALSE_VALUE, false);
        return emit(IDENTIFIER, text);
    }

    int finishLiteral(TokenKind type) {
        buffer.restoreStart();
        return emit(type, buffer.current());
    }

    int unfinished(const char* message) {
        buffer.restoreStart();
        return error(message);
    }

    #define YY_USER_ACTION buffer.trackPosition(yytext, size_t(yyleng));
%}

%x COMMENT STRING READ_CHARACTER

/* ============================================================
   Именованные регулярные выражения
   ============================================================ */

DIGIT                  [0-9]
DECIMAL_DIGITS         {DIGIT}[0-9_]*
IDENTIFIER_TEXT        [A-Za-z][A-Za-z0-9_$]*
KEYWORD_PART           {IDENTIFIER_TEXT}:
SYMBOL_TEXT            [A-Za-z_$:][A-Za-z0-9_$:]*
BINARY_CHARACTER       [%&*+,/<=>?@\\~|-]
BINARY_SELECTOR_TEXT   {BINARY_CHARACTER}{1,2}

/* лишний хвост возвращаем через yyless */
NUMBER_TEXT            {DECIMAL_DIGITS}(r-?[0-9A-Z_]*)?(\.[0-9A-Z_]+)?([edqs]-?[0-9_]*)?[A-Za-z_$]?

SPACES                 [ \t\r\n\f]+
CHARACTER              (.|\n)

%%

    /* ============================================================
       Пробельные символы
       ============================================================ */

^"#!"[^\r\n]*                             {
    if (buffer.tokenStart.offset != 0) {
        yyless(1);
        buffer.keepPrefix(1);
        return emit(HASH);
    }
}

{SPACES}                                    { } // Пример: пробел, табуляция или перевод строки -> пропуск между токенами.

    /* ============================================================
       Комментарии Smalltalk: двойные кавычки
       ============================================================ */

\"[^\"]*\"                                { } // Пример: "note" или "" -> пропустить комментарий.

\"                                          { // Пример: "unfinished без закрывающей кавычки -> начать чтение комментария.
    buffer.reset();
    BEGIN(COMMENT);
}
<COMMENT>[^\"]+                            { } // Пример: unfinished -> пропустить текст, включая переводы строк.
<COMMENT>\"                                 { // Пример: закрывающая " -> выход из комментария.
    BEGIN(INITIAL);
    buffer.restoreStart();
}
<COMMENT><<EOF>>                            { // Пример: файл закончился после "unfinished -> ошибка: комментарий не закрыт.
    BEGIN(INITIAL);
    return unfinished("Unterminated comment");
}

    /* ============================================================
       Числовые значения: INTEGER, FLOAT, SCALED_DECIMAL
       ============================================================ */

{NUMBER_TEXT}                               {
    NumberValue parsed = Buffer::parseNumber(buffer.lexeme);
    if (parsed.length < size_t(yyleng)) {
        yyless(int(parsed.length));
        buffer.keepPrefix(parsed.length);
    }
    return emit(parsed.type, parsed.value, parsed.details);
}

    /* ============================================================
       Имена, псевдопеременные и части keyword-селекторов
       ============================================================ */

{IDENTIFIER_TEXT}/(":="|"::")                      { return identifier(buffer.lexeme); } // Пример: x:=1 -> сначала IDENTIFIER(x), затем ASSIGN.
{KEYWORD_PART}                              { return emit(KEYWORD, buffer.lexeme); } // Пример: at:, put:, whileTrue: -> KEYWORD; self: тоже KEYWORD.

"self"                                      { return emit(SELF); } // Пример: self -> SELF; selfish -> IDENTIFIER.
"super"                                     { return emit(SUPER); } // Пример: super -> SUPER; superClass -> IDENTIFIER.
"nil"                                       { return emit(NIL_VALUE); } // Пример: nil -> NIL; nil2 -> IDENTIFIER.
"true"                                      { return emit(TRUE_VALUE, true); } // Пример: true -> TRUE; True -> IDENTIFIER.
"false"                                     { return emit(FALSE_VALUE, false); } // Пример: false -> FALSE; false2 -> IDENTIFIER.

{IDENTIFIER_TEXT}                           { return identifier(buffer.lexeme); } // Пример: x, Person, size, a_b, a$b -> IDENTIFIER; роль определяет parser.

    /* ============================================================
       Строки и символы в кавычках: STRING, SYMBOL
       ============================================================ */

"#'"                                        { // Пример: #'Hello world' -> SYMBOL; используется состояние строки.
    buffer.reset();
    stringKind = SYMBOL;
    BEGIN(STRING);
}
"'"                                         { // Пример: 'Hello', '' -> STRING; открывающая кавычка не входит в value.
    buffer.reset();
    stringKind = STRING_VALUE;
    BEGIN(STRING);
}
<STRING>"''"                                { buffer.append("'", 1); } // Пример: 'can''t' -> value="can't"; два апострофа дают один.
<STRING>[^']+                               { buffer.append(yytext, size_t(yyleng)); } // Пример: '\n' сохраняет два символа: backslash и n.
<STRING>"'"                                 { // Пример: закрывающая ' -> STRING или SYMBOL.
    BEGIN(INITIAL);
    return finishLiteral(stringKind);
}
<STRING><<EOF>>                             { // Пример: 'abc или #'abc + EOF -> ERROR, затем EOF.
    BEGIN(INITIAL);
    return unfinished(stringKind == SYMBOL ? "Unterminated quoted symbol" : "Unterminated string");
}

    /* ============================================================
       Символьные значения: CHARACTER
       ============================================================ */

"$"                                         { // Пример: $A -> начать чтение одного символа после $.
    buffer.reset();
    BEGIN(READ_CHARACTER);
}
<READ_CHARACTER>{CHARACTER}                 { // Пример: $+, $$, $", $' или перевод строки после $ -> CHARACTER.
    BEGIN(INITIAL);
    buffer.restoreStart();
    return emit(CHAR_VALUE, yytext[0]);
}
<READ_CHARACTER><<EOF>>                     { // Пример: одиночный $ + EOF -> ERROR, затем EOF.
    BEGIN(INITIAL);
    return unfinished("Expected character after $");
}

    /* ============================================================
       Литеральные селекторы: SELECTOR
       ============================================================ */

"#"{SYMBOL_TEXT}                            { return emit(SELECTOR, buffer.lexeme.substr(1)); } // Пример: #at:put:next, #:, #_x -> один Symbol.
"#"{BINARY_CHARACTER}"-"/{DIGIT}            {
    yyless(2);
    buffer.keepPrefix(2);
    return emit(SELECTOR, buffer.lexeme.substr(1));
}
"#"{BINARY_SELECTOR_TEXT}                   { return emit(SELECTOR, buffer.lexeme.substr(1)); } // Пример: #+, #<=, #>> -> SELECTOR; #>>> -> SELECTOR(>>) и BINARY_SELECTOR(>).

    /* ============================================================
       Присваивание, возврат и бинарные селекторы
       ============================================================ */

":="|"_"                                    { return emit(ASSIGN); } // Пример: x:=1 -> ASSIGN после IDENTIFIER(x).
"^"                                         { return emit(RETURN); } // Пример: ^self -> RETURN, SELF.

{BINARY_CHARACTER}"-"/{DIGIT}               {
    yyless(1);
    buffer.keepPrefix(1);
    if (buffer.lexeme == "-") {
        return emit(MINUS, buffer.lexeme);
    }

    if (buffer.lexeme == "|") {
        return emit(BAR, buffer.lexeme);
    }

    return emit(BINARY_SELECTOR, buffer.lexeme);
}
"!"                                         { return emit(CHUNK_END); }
"-"                                         { return emit(MINUS, buffer.lexeme); } // Пример: -15 -> MINUS + INTEGER; одиночный - также бинарный селектор.
"|"                                         { return emit(BAR, buffer.lexeme); } // Пример: | x y | -> BAR; одиночный | также бинарный селектор.
{BINARY_SELECTOR_TEXT}                      { return emit(BINARY_SELECTOR, buffer.lexeme); } // Пример: <=, ==, --, ||, |+ -> один BINARY_SELECTOR; >>> -> >> и >.

    /* ============================================================
       Скобки, начало массива, аргументы блока и разделители
       ============================================================ */

"#"                                         { return emit(HASH); } // Пример: #(1) или # (1) -> HASH, LPAREN, INTEGER, RPAREN.
"("                                         { return emit(LPAREN); } // Пример: (x) -> LPAREN.
")"                                         { return emit(RPAREN); } // Пример: (x) или #(1) -> RPAREN.
"["                                         { return emit(LBRACKET); } // Пример: [1] -> LBRACKET.
"]"                                         { return emit(RBRACKET); } // Пример: [1] -> RBRACKET.
"::"                                        { return emit(SCOPE_SEPARATOR); }
":"                                         { return emit(COLON); } // Пример: [:x | x] -> COLON, IDENTIFIER(x).
"."/[A-Za-z0-9_$]                           {
    bool name = currentToken.type == IDENTIFIER || currentToken.type == SELF
             || currentToken.type == SUPER || currentToken.type == TRUE_VALUE
             || currentToken.type == FALSE_VALUE || currentToken.type == NIL_VALUE;
    if (!name) {
        return emit(PERIOD);
    }

    if (currentToken.end.offset != buffer.tokenStart.offset) {
        return emit(PERIOD);
    }

    return emit(SCOPE_SEPARATOR);
}
"."                                         { return emit(PERIOD); } // Пример: 1. -> INTEGER(1), PERIOD; 1.5 -> один FLOAT.
";"                                         { return emit(SEMICOLON); } // Пример: Transcript show: 'a'; cr -> SEMICOLON.

    /* ============================================================
       Нераспознанные знаки и конец входа
       ============================================================ */

"{"                                         { return emit(LBRACE); }
"}"                                         { return emit(RBRACE); }
.                                           { return error("Unexpected source character"); } // Пример: backtick вне литерала -> ERROR; в exclusive states действуют свои правила.

<INITIAL><<EOF>>                            { // Пример: пустой файл или EOF после готового токена -> 0.
    buffer.tokenStart = buffer.position;
    buffer.lexeme.clear();
    return 0;
}
%%

int main(int argc, char** argv) {
    if (argc != 2) {
        Console::Error("Usage: lexer file.st");
        return 2;
    }

    yyin = fopen(argv[1], "rb");
    if (!yyin) {
        Console::Error(string("Cannot open ") + argv[1]);
        return 2;
    }

    while (yylex() != 0) {}

    bool readError = ferror(yyin) != 0;
    fclose(yyin);
    yylex_destroy();
    Console::Summary(tokenCount, errorCount);

    if (readError) {
        Console::Error("Cannot read input");
        return 2;
    }
    if (errorCount > 0) {
        return 1;
    }
    return 0;
}
