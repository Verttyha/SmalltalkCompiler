%option noyywrap never-interactive
%option noinput nounput nodefault nounistd 8bit

%{
    // потом в buffer h
    #include <cmath>
    #include <cstddef>
    #include <stdexcept>
    #include <string>
    #include <variant>

    enum TokenKind {
        IDENTIFIER = 256, KEYWORD, SELF, SUPER, TRUE_VALUE, FALSE_VALUE,
        NIL_VALUE, LEX_ERROR
    };

    struct Position {
        std::size_t line = 1, column = 1, offset = 0;
    };

    // добавить точность для целых больше long long?
    using IntegerValue = long long;

    // добавить точность для scaled decimal?
    struct DecimalValue {
        double value;
        std::size_t scale;
    };

    using TokenValue = std::variant<std::monostate, IntegerValue, double,
                                    DecimalValue, char, bool, std::string>;

    struct Token {
        TokenKind type;
        TokenValue value;
        std::string details;
        std::string lexeme;
        Position start, end;
    };

    class Buffer {
    public:
        Position position;
        Position tokenStart;
        std::string lexeme;

        void trackPosition(const char* text, std::size_t length) {
            tokenStart = position;

            lexeme.assign(text, length);

            for (std::size_t i = 0; i < length; ++i) {
                unsigned char c = text[i];
                ++position.offset;

                if (c == '\r') {
                    ++position.line;
                    position.column = 1;
                } else if (c == '\n') {
                    if (!previousCR) ++position.line;
                    position.column = 1;
                } else {
                    ++position.column;
                }

                previousCR = c == '\r';
            }
        }

        void keepPrefix(std::size_t length) {
            lexeme.resize(length);
            position = tokenStart;
            position.column += length;
            position.offset += length;
            previousCR = false;
        }


    private:
        bool previousCR = false;
    };

    // потом в console h
    #include <iomanip>
    #include <iostream>
    #include <limits>

    inline const char* TokenName(TokenKind type) {
        static const char* const names[] = {
            "IDENTIFIER", "KEYWORD", "SELF", "SUPER", "TRUE", "FALSE",
            "NIL", "ERROR"
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
            case IDENTIFIER: case KEYWORD:
                PrintString(std::get<std::string>(token.value));
                break;

            case LEX_ERROR:
                PrintString(std::get<std::string>(token.value));
                std::cout << " lexeme=";
                PrintString(token.lexeme);
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

    #define YY_USER_ACTION buffer.trackPosition(yytext, size_t(yyleng));
%}

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


{SPACES}                                    { } // Пример: пробел, табуляция или перевод строки -> пропуск между токенами.

    /* ============================================================
       Комментарии Smalltalk: двойные кавычки
       ============================================================ */

    /* потом комментарии */

    /* ============================================================
       Числовые значения: INTEGER, FLOAT, SCALED_DECIMAL
       ============================================================ */

    /* потом числа */

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

    /* потом строки */

    /* ============================================================
       Символьные значения: CHARACTER
       ============================================================ */

    /* потом символ после $ */

    /* ============================================================
       Литеральные селекторы: SELECTOR
       ============================================================ */

    /* потом литеральные селекторы */

    /* ============================================================
       Присваивание, возврат и бинарные селекторы
       ============================================================ */

    /* потом операции */

    /* ============================================================
       Скобки, начало массива, аргументы блока и разделители
       ============================================================ */

    /* потом скобки и разделители */

    /* ============================================================
       Нераспознанные знаки и конец входа
       ============================================================ */

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
