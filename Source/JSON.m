// JSON.m
//
// Recursive descent over UTF-8 bytes. Strings without escapes become
// NSStrings directly. Strings with escapes are rebuilt as UTF-8 first, with
// \uXXXX surrogate pairs combined.

#import "JSON.h"

typedef struct {
    const uint8_t *p;
    const uint8_t *end;
    const char *problem;
    int depth;
} LTVJSONReader;

static id LTVParseValue(LTVJSONReader *r);

static id LTVFail(LTVJSONReader *r, const char *problem)
{
    if (r->problem == NULL)
        r->problem = problem;
    return nil;
}

static void LTVSkipSpace(LTVJSONReader *r)
{
    while (r->p < r->end && (*r->p == ' ' || *r->p == '\t' || *r->p == '\n' || *r->p == '\r'))
        r->p++;
}

static int LTVHexValue(const uint8_t *p)
{
    int value = 0;
    for (int i = 0; i < 4; i++) {
        int c = p[i], digit;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
        else return -1;
        value = value * 16 + digit;
    }
    return value;
}

static size_t LTVAppendUTF8(uint8_t *out, unsigned codePoint)
{
    if (codePoint < 0x80) {
        out[0] = (uint8_t)codePoint;
        return 1;
    }
    if (codePoint < 0x800) {
        out[0] = (uint8_t)(0xC0 | (codePoint >> 6));
        out[1] = (uint8_t)(0x80 | (codePoint & 0x3F));
        return 2;
    }
    if (codePoint < 0x10000) {
        out[0] = (uint8_t)(0xE0 | (codePoint >> 12));
        out[1] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
        out[2] = (uint8_t)(0x80 | (codePoint & 0x3F));
        return 3;
    }
    out[0] = (uint8_t)(0xF0 | (codePoint >> 18));
    out[1] = (uint8_t)(0x80 | ((codePoint >> 12) & 0x3F));
    out[2] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
    out[3] = (uint8_t)(0x80 | (codePoint & 0x3F));
    return 4;
}

static NSString *LTVParseString(LTVJSONReader *r)
{
    const uint8_t *start = ++r->p;
    BOOL escaped = NO;
    while (r->p < r->end && *r->p != '"') {
        if (*r->p == '\\') {
            escaped = YES;
            r->p++;
        }
        r->p++;
    }
    if (r->p >= r->end)
        return LTVFail(r, "unterminated string");
    const uint8_t *stop = r->p++;

    if (!escaped)
        return [[[NSString alloc] initWithBytes:start length:stop - start encoding:NSUTF8StringEncoding] autorelease];

    // Escapes never make the UTF-8 longer than the escaped source.
    uint8_t *out = malloc(stop - start);
    size_t length = 0;
    for (const uint8_t *q = start; q < stop; ) {
        if (*q != '\\') {
            out[length++] = *q++;
            continue;
        }
        q++;
        switch (*q) {
            case '"':  out[length++] = '"';  q++; break;
            case '\\': out[length++] = '\\'; q++; break;
            case '/':  out[length++] = '/';  q++; break;
            case 'b':  out[length++] = '\b'; q++; break;
            case 'f':  out[length++] = '\f'; q++; break;
            case 'n':  out[length++] = '\n'; q++; break;
            case 'r':  out[length++] = '\r'; q++; break;
            case 't':  out[length++] = '\t'; q++; break;
            case 'u': {
                int unit = stop - q >= 5 ? LTVHexValue(q + 1) : -1;
                if (unit < 0) {
                    free(out);
                    return LTVFail(r, "bad \\u escape");
                }
                q += 5;
                unsigned codePoint = (unsigned)unit;
                if (unit >= 0xD800 && unit <= 0xDBFF) {
                    int low = (stop - q >= 6 && q[0] == '\\' && q[1] == 'u') ? LTVHexValue(q + 2) : -1;
                    if (low >= 0xDC00 && low <= 0xDFFF) {
                        codePoint = 0x10000 + ((unsigned)(unit - 0xD800) << 10) + (unsigned)(low - 0xDC00);
                        q += 6;
                    } else {
                        codePoint = 0xFFFD;
                    }
                } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
                    codePoint = 0xFFFD;
                }
                length += LTVAppendUTF8(out + length, codePoint);
                break;
            }
            default:
                free(out);
                return LTVFail(r, "bad escape");
        }
    }
    NSString *string = [[[NSString alloc] initWithBytes:out length:length encoding:NSUTF8StringEncoding] autorelease];
    free(out);
    return string;
}

static NSNumber *LTVParseNumber(LTVJSONReader *r)
{
    char buffer[64];
    size_t length = 0;
    BOOL fraction = NO;
    while (r->p < r->end && length < sizeof buffer - 1) {
        uint8_t c = *r->p;
        if ((c >= '0' && c <= '9') || c == '-' || c == '+')
            ;
        else if (c == '.' || c == 'e' || c == 'E')
            fraction = YES;
        else
            break;
        buffer[length++] = (char)c;
        r->p++;
    }
    buffer[length] = '\0';
    if (length == 0)
        return LTVFail(r, "bad number");
    if (fraction)
        return [NSNumber numberWithDouble:strtod(buffer, NULL)];
    return [NSNumber numberWithLongLong:strtoll(buffer, NULL, 10)];
}

static BOOL LTVMatch(LTVJSONReader *r, const char *word)
{
    size_t length = strlen(word);
    if ((size_t)(r->end - r->p) < length || memcmp(r->p, word, length) != 0)
        return NO;
    r->p += length;
    return YES;
}

static NSArray *LTVParseArray(LTVJSONReader *r)
{
    r->p++;
    NSMutableArray *array = [NSMutableArray array];
    LTVSkipSpace(r);
    if (r->p < r->end && *r->p == ']') {
        r->p++;
        return array;
    }
    while (r->p < r->end) {
        id value = LTVParseValue(r);
        if (value == nil)
            return nil;
        [array addObject:value];
        LTVSkipSpace(r);
        if (r->p < r->end && *r->p == ',') {
            r->p++;
            continue;
        }
        if (r->p < r->end && *r->p == ']') {
            r->p++;
            return array;
        }
        break;
    }
    return LTVFail(r, "bad array");
}

static NSDictionary *LTVParseObject(LTVJSONReader *r)
{
    r->p++;
    NSMutableDictionary *object = [NSMutableDictionary dictionary];
    LTVSkipSpace(r);
    if (r->p < r->end && *r->p == '}') {
        r->p++;
        return object;
    }
    while (r->p < r->end) {
        LTVSkipSpace(r);
        if (r->p >= r->end || *r->p != '"')
            break;
        NSString *key = LTVParseString(r);
        if (key == nil)
            return nil;
        LTVSkipSpace(r);
        if (r->p >= r->end || *r->p != ':')
            break;
        r->p++;
        id value = LTVParseValue(r);
        if (value == nil)
            return nil;
        [object setObject:value forKey:key];
        LTVSkipSpace(r);
        if (r->p < r->end && *r->p == ',') {
            r->p++;
            continue;
        }
        if (r->p < r->end && *r->p == '}') {
            r->p++;
            return object;
        }
        break;
    }
    return LTVFail(r, "bad object");
}

static id LTVParseValue(LTVJSONReader *r)
{
    LTVSkipSpace(r);
    if (r->p >= r->end)
        return LTVFail(r, "unexpected end");
    if (++r->depth > 64)
        return LTVFail(r, "nested too deeply");
    id value;
    switch (*r->p) {
        case '{': value = LTVParseObject(r); break;
        case '[': value = LTVParseArray(r); break;
        case '"': value = LTVParseString(r); break;
        case 't': value = LTVMatch(r, "true") ? [NSNumber numberWithBool:YES] : LTVFail(r, "bad word"); break;
        case 'f': value = LTVMatch(r, "false") ? [NSNumber numberWithBool:NO] : LTVFail(r, "bad word"); break;
        case 'n': value = LTVMatch(r, "null") ? [NSNull null] : LTVFail(r, "bad word"); break;
        default:  value = LTVParseNumber(r); break;
    }
    r->depth--;
    return value;
}

id LTVJSONParse(NSData *data, NSError **error)
{
    LTVJSONReader reader = { [data bytes], (const uint8_t *)[data bytes] + [data length], NULL, 0 };
    id value = LTVParseValue(&reader);
    if (value != nil) {
        LTVSkipSpace(&reader);
        if (reader.p != reader.end)
            value = LTVFail(&reader, "extra text after the value");
    }
    if (value == nil && error != NULL) {
        NSString *message = [NSString stringWithFormat:@"The server's reply isn't valid JSON (%s at byte %ld).",
                             reader.problem, (long)(reader.p - (const uint8_t *)[data bytes])];
        *error = [NSError errorWithDomain:@"LTVJSON" code:1
                                 userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
    }
    return value;
}
