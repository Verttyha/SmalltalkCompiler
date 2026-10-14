#define main lexerMain
#include "lexer.cpp"
#undef main

#include <cassert>
#include <fstream>
#include <iterator>
#include <sstream>

static Position positionAt(const std::string& source, std::size_t offset) {
    Position position;
    bool previousCR = false;
    for (std::size_t i = 0; i < offset; ++i) {
        char c = source[i];
        ++position.offset;
        if (c == '\r') { ++position.line; position.column = 1; }
        else if (c == '\n') { if (!previousCR) ++position.line; position.column = 1; }
        else ++position.column;
        previousCR = c == '\r';
    }
    return position;
}

int main(int argc, char** argv) {
    std::ostringstream output;
    auto previousOutput = std::cout.rdbuf(output.rdbuf());
    for (int i = 1; i < argc; ++i) {
        std::ifstream file(argv[i], std::ios::binary);
        assert(file);
        std::string source((std::istreambuf_iterator<char>(file)), {});
        FILE* input = fopen(argv[i], "rb");
        assert(input);
        buffer = Buffer{};
        currentToken = Token{};
        stringKind = STRING_VALUE;
        tokenCount = errorCount = 0;
        BEGIN(INITIAL);
        yyrestart(input);
        std::size_t previousEnd = 0;
        while (yylex() != 0) {
            const Token& token = currentToken;
            assert(token.start.offset >= previousEnd && token.end.offset >= token.start.offset);
            assert(token.end.offset <= source.size());
            assert(token.lexeme == source.substr(token.start.offset, token.end.offset - token.start.offset));
            Position start = positionAt(source, token.start.offset), end = positionAt(source, token.end.offset);
            assert(token.start.line == start.line && token.start.column == start.column);
            assert(token.end.line == end.line && token.end.column == end.column);
            previousEnd = token.end.offset;
        }
        assert(buffer.position.offset == source.size());
        fclose(input);
        output.str("");
    }
    yylex_destroy();
    std::cout.rdbuf(previousOutput);
    std::cout << argc - 1 << " span checks passed\n";
}
