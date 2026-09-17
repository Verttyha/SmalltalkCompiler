%option noyywrap never-interactive
%option noinput nounput nodefault nounistd 8bit

%{
    #include <cstdio>
%}

%%

(.|\n)                                     { }

%%

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    yyin = fopen(argv[1], "rb");
    if (!yyin) return 2;
    while (yylex() != 0) {}
    fclose(yyin);
    yylex_destroy();
    return 0;
}
