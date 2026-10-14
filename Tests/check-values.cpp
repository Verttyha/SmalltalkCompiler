#include "Buffer.h"
#include <cassert>
#include <iostream>
#include <limits>

int main() {
    assert(std::get<IntegerValue>(Buffer::parseNumber("1_000").value) == 1000);
    assert(std::get<IntegerValue>(Buffer::parseNumber("16rFF").value) == 255);
    assert(std::get<IntegerValue>(Buffer::parseNumber("16r-FF").value) == -255);
    assert(std::get<IntegerValue>(Buffer::parseNumber("16r_FF").value) == 255);
    assert(std::get<IntegerValue>(Buffer::parseNumber("2r101").value) == 5);
    assert(std::get<IntegerValue>(Buffer::parseNumber("36rZ").value) == 35);
    assert(std::get<IntegerValue>(Buffer::parseNumber("1r0").value) == 0);
    assert(std::get<IntegerValue>(Buffer::parseNumber("16r-0").value) == 0);
    assert(std::get<IntegerValue>(Buffer::parseNumber("9223372036854775807").value) == std::numeric_limits<IntegerValue>::max());
    assert(std::get<IntegerValue>(Buffer::parseNumber("16r-8000000000000000").value) == std::numeric_limits<IntegerValue>::min());

    for (char format : {'e', 'd', 'q'}) {
        auto parsed = Buffer::parseNumber(std::string("1.23456789") + format + "0");
        assert(std::get<double>(parsed.value) == 1.23456789);
        assert(parsed.details == std::string("format=") + format);
        assert(std::get<double>(Buffer::parseNumber(std::string("1") + format).value) == 1);
        assert(std::get<double>(Buffer::parseNumber(std::string("1") + format + "3").value) == 1000);
    }
    assert(std::get<double>(Buffer::parseNumber("1_000.0_5").value) == 1000.05);
    assert(std::get<double>(Buffer::parseNumber("1.0e-3").value) == 0.001);
    assert(std::get<double>(Buffer::parseNumber("0.0q9999").value) == 0);
    assert(std::get<double>(Buffer::parseNumber("2r1.1").value) == 1.5);
    assert(std::get<double>(Buffer::parseNumber("16rA.F").value) == 10.9375);
    assert(std::get<double>(Buffer::parseNumber("16r-FF.8").value) == -255.5);
    assert(std::get<double>(Buffer::parseNumber("16rA.Fe2").value) == 2800);
    assert(std::get<double>(Buffer::parseNumber("16rA.Fq-1").value) == 0.68359375);
    assert(std::signbit(std::get<double>(Buffer::parseNumber("16r-0.0q0").value)));

    auto scaled = std::get<DecimalValue>(Buffer::parseNumber("1.25s1").value);
    assert(scaled.value == 1.25 && scaled.scale == 1);
    auto defaultScale = std::get<DecimalValue>(Buffer::parseNumber("1.250s").value);
    assert(defaultScale.value == 1.25 && defaultScale.scale == 3);
    auto integerScale = std::get<DecimalValue>(Buffer::parseNumber("1s1000001").value);
    assert(integerScale.value == 1 && integerScale.scale == 1000001);
    auto radixScale = std::get<DecimalValue>(Buffer::parseNumber("16rA.Fs2").value);
    assert(radixScale.value == 10.9375 && radixScale.scale == 2);
    auto separatedScale = std::get<DecimalValue>(Buffer::parseNumber("1_2.3_4s2_0").value);
    assert(separatedScale.value == 12.34 && separatedScale.scale == 20);

    for (const char* text : {"9223372036854775808", "16r-8000000000000001", "999999999999999999999999999",
                             "1q400", "1e9999", "1e-9999", "16r1q9999", "1s999999999999999999999999",
                             "16r0.0q999999999999999999999", "16r0.0q-999999999999999999999"}) {
        auto parsed = Buffer::parseNumber(text);
        assert(parsed.type == LEX_ERROR);
        assert(std::get<std::string>(parsed.value) == "Number is outside the supported range");
        assert(parsed.length == std::string(text).size());
    }
    const struct { const char* text; std::size_t length; TokenKind type; } boundaries[] = {
        {"1.0e3negated", 5, FLOAT_VALUE},
        {"1eabs", 2, FLOAT_VALUE},
        {"1dnegated", 2, FLOAT_VALUE},
        {"1.0e-foo", 5, LEX_ERROR},
        {"12sfoo", 2, INTEGER},
        {"12s_2", 2, INTEGER},
        {"16rFFsqrt", 5, INTEGER},
        {"2r102", 4, INTEGER},
        {"16r0._F", 4, INTEGER},
        {"37rFF", 3, LEX_ERROR},
        {"1r1", 2, LEX_ERROR},
        {"16r___", 6, LEX_ERROR},
    };
    for (const auto& sample : boundaries) {
        auto parsed = Buffer::parseNumber(sample.text);
        assert(parsed.length == sample.length && parsed.type == sample.type);
    }

    std::cout << "Value checks passed\n";
}
