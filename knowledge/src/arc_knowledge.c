#include "arc_knowledge.h"

#include <stdint.h>
#include <string.h>

#define ARC_KNOWLEDGE_HEADER_BYTES 64u
#define ARC_KNOWLEDGE_ENTRY_BYTES 160u
#define ARC_KNOWLEDGE_MAX_BYTES 8388608u
#define ARC_KNOWLEDGE_MAX_MEMBER_BYTES 524288u
#define ARC_KNOWLEDGE_MEMBER_COUNT 19u
#define ARC_KNOWLEDGE_MAGIC UINT64_C(0x4152434b4e4f5731)

typedef struct ArcKnowledgeSlot {
    size_t offset;
    size_t length;
    unsigned char sha256[32];
    unsigned char state;
} ArcKnowledgeSlot;

struct ArcKnowledge {
    uint64_t magic;
    const struct ArcKnowledge *self;
    const unsigned char *source;
    size_t source_length;
    unsigned char source_sha256[32];
    ArcKnowledgeSlot members[ARC_KNOWLEDGE_MEMBER_COUNT];
};

typedef struct ArcSha256 {
    uint32_t state[8];
    uint64_t total_bytes;
    unsigned char block[64];
    size_t block_length;
} ArcSha256;

typedef struct ArcProfileMember {
    const char *name;
    ArcKnowledgeMember member;
    unsigned char required;
} ArcProfileMember;

static const ArcProfileMember arc_profile_members[] = {
    {"ai/arc-ai.txt", ARC_KNOWLEDGE_AI_GUIDE, 1u},
    {"help/arc-help.txt", ARC_KNOWLEDGE_HELP, 1u},
    {"legal/hummingbird-license.txt", ARC_KNOWLEDGE_LICENSE, 1u},
    {"legal/notice.txt", ARC_KNOWLEDGE_NOTICE, 1u},
    {"manual/arc-man-page.txt", ARC_KNOWLEDGE_MAN_PAGE, 1u},
    {"release/release-notes.txt", ARC_KNOWLEDGE_RELEASE_NOTES, 0u},
    {"specifications/000-shared-constitution.txt", ARC_KNOWLEDGE_SPEC_000, 1u},
    {"specifications/001-shared-how-to-read-these-specs.txt",
     ARC_KNOWLEDGE_SPEC_001, 1u},
    {"specifications/002-arc-room-administrator-ai-and-producer.txt",
     ARC_KNOWLEDGE_SPEC_002, 1u},
    {"specifications/003-arc-durable-state-and-integrity.txt",
     ARC_KNOWLEDGE_SPEC_003, 1u},
    {"specifications/004-arc-messaging-and-work-protocol.txt",
     ARC_KNOWLEDGE_SPEC_004, 1u},
    {"specifications/005-arc-ai-instructions-qualification-duty-and-polling.txt",
     ARC_KNOWLEDGE_SPEC_005, 1u},
    {"specifications/006-arc-macos-application-contract.txt",
     ARC_KNOWLEDGE_SPEC_006, 1u},
    {"specifications/007-arc-cli-machine-interface.txt",
     ARC_KNOWLEDGE_SPEC_007, 1u},
    {"specifications/008-arc-security-and-privacy.txt",
     ARC_KNOWLEDGE_SPEC_008, 1u},
    {"specifications/009-arc-installation-distribution-and-release.txt",
     ARC_KNOWLEDGE_SPEC_009, 1u},
    {"specifications/010-arc-specification-traceability-and-dvt-readiness.txt",
     ARC_KNOWLEDGE_SPEC_010, 1u},
    {"specifications/011-arc-durable-record-contract.txt",
     ARC_KNOWLEDGE_SPEC_011, 1u},
    {"specifications/012-arc-ai-knowledge-container.txt",
     ARC_KNOWLEDGE_SPEC_012, 1u}
};

static const uint32_t arc_sha256_constants[64] = {
    UINT32_C(0x428a2f98), UINT32_C(0x71374491), UINT32_C(0xb5c0fbcf),
    UINT32_C(0xe9b5dba5), UINT32_C(0x3956c25b), UINT32_C(0x59f111f1),
    UINT32_C(0x923f82a4), UINT32_C(0xab1c5ed5), UINT32_C(0xd807aa98),
    UINT32_C(0x12835b01), UINT32_C(0x243185be), UINT32_C(0x550c7dc3),
    UINT32_C(0x72be5d74), UINT32_C(0x80deb1fe), UINT32_C(0x9bdc06a7),
    UINT32_C(0xc19bf174), UINT32_C(0xe49b69c1), UINT32_C(0xefbe4786),
    UINT32_C(0x0fc19dc6), UINT32_C(0x240ca1cc), UINT32_C(0x2de92c6f),
    UINT32_C(0x4a7484aa), UINT32_C(0x5cb0a9dc), UINT32_C(0x76f988da),
    UINT32_C(0x983e5152), UINT32_C(0xa831c66d), UINT32_C(0xb00327c8),
    UINT32_C(0xbf597fc7), UINT32_C(0xc6e00bf3), UINT32_C(0xd5a79147),
    UINT32_C(0x06ca6351), UINT32_C(0x14292967), UINT32_C(0x27b70a85),
    UINT32_C(0x2e1b2138), UINT32_C(0x4d2c6dfc), UINT32_C(0x53380d13),
    UINT32_C(0x650a7354), UINT32_C(0x766a0abb), UINT32_C(0x81c2c92e),
    UINT32_C(0x92722c85), UINT32_C(0xa2bfe8a1), UINT32_C(0xa81a664b),
    UINT32_C(0xc24b8b70), UINT32_C(0xc76c51a3), UINT32_C(0xd192e819),
    UINT32_C(0xd6990624), UINT32_C(0xf40e3585), UINT32_C(0x106aa070),
    UINT32_C(0x19a4c116), UINT32_C(0x1e376c08), UINT32_C(0x2748774c),
    UINT32_C(0x34b0bcb5), UINT32_C(0x391c0cb3), UINT32_C(0x4ed8aa4a),
    UINT32_C(0x5b9cca4f), UINT32_C(0x682e6ff3), UINT32_C(0x748f82ee),
    UINT32_C(0x78a5636f), UINT32_C(0x84c87814), UINT32_C(0x8cc70208),
    UINT32_C(0x90befffa), UINT32_C(0xa4506ceb), UINT32_C(0xbef9a3f7),
    UINT32_C(0xc67178f2)
};

_Static_assert(sizeof(struct ArcKnowledge) <= ARC_KNOWLEDGE_WORKSPACE_BYTES,
               "ArcKnowledge exceeds its fixed workspace");
_Static_assert(sizeof(ArcKnowledgeStorage) == ARC_KNOWLEDGE_WORKSPACE_BYTES,
               "ArcKnowledgeStorage has an unexpected size");
_Static_assert(ARC_KNOWLEDGE_RELEASE_NOTES + 1 ==
                   ARC_KNOWLEDGE_MEMBER_COUNT,
               "ArcKnowledgeMember has an unexpected size");
_Static_assert(
    sizeof(arc_profile_members) / sizeof(arc_profile_members[0]) ==
        ARC_KNOWLEDGE_MEMBER_COUNT,
    "Profile 1 member table has an unexpected size");

static uint32_t arc_rotr32(uint32_t value, unsigned int count)
{
    return (value >> count) | (value << (32u - count));
}

static uint32_t arc_read_u32(const unsigned char *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint64_t arc_read_u64(const unsigned char *bytes)
{
    return ((uint64_t)arc_read_u32(bytes) << 32) |
           (uint64_t)arc_read_u32(bytes + 4);
}

static uint16_t arc_read_u16(const unsigned char *bytes)
{
    return (uint16_t)(((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1]);
}

static void arc_write_u64(unsigned char *bytes, uint64_t value)
{
    size_t index;

    for (index = 0u; index < 8u; ++index) {
        bytes[7u - index] = (unsigned char)(value & UINT64_C(0xff));
        value >>= 8;
    }
}

static void arc_sha256_transform(ArcSha256 *context,
                                 const unsigned char block[64])
{
    uint32_t words[64];
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;
    size_t index;

    for (index = 0u; index < 16u; ++index) {
        words[index] = arc_read_u32(block + (index * 4u));
    }
    for (index = 16u; index < 64u; ++index) {
        uint32_t s0 = arc_rotr32(words[index - 15u], 7u) ^
                      arc_rotr32(words[index - 15u], 18u) ^
                      (words[index - 15u] >> 3u);
        uint32_t s1 = arc_rotr32(words[index - 2u], 17u) ^
                      arc_rotr32(words[index - 2u], 19u) ^
                      (words[index - 2u] >> 10u);
        words[index] = words[index - 16u] + s0 + words[index - 7u] + s1;
    }

    a = context->state[0];
    b = context->state[1];
    c = context->state[2];
    d = context->state[3];
    e = context->state[4];
    f = context->state[5];
    g = context->state[6];
    h = context->state[7];

    for (index = 0u; index < 64u; ++index) {
        uint32_t upper = arc_rotr32(e, 6u) ^ arc_rotr32(e, 11u) ^
                         arc_rotr32(e, 25u);
        uint32_t choose = (e & f) ^ ((~e) & g);
        uint32_t first = h + upper + choose +
                         arc_sha256_constants[index] + words[index];
        uint32_t lower = arc_rotr32(a, 2u) ^ arc_rotr32(a, 13u) ^
                         arc_rotr32(a, 22u);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t second = lower + majority;

        h = g;
        g = f;
        f = e;
        e = d + first;
        d = c;
        c = b;
        b = a;
        a = first + second;
    }

    context->state[0] += a;
    context->state[1] += b;
    context->state[2] += c;
    context->state[3] += d;
    context->state[4] += e;
    context->state[5] += f;
    context->state[6] += g;
    context->state[7] += h;
}

static void arc_sha256_init(ArcSha256 *context)
{
    static const uint32_t initial[8] = {
        UINT32_C(0x6a09e667), UINT32_C(0xbb67ae85),
        UINT32_C(0x3c6ef372), UINT32_C(0xa54ff53a),
        UINT32_C(0x510e527f), UINT32_C(0x9b05688c),
        UINT32_C(0x1f83d9ab), UINT32_C(0x5be0cd19)
    };

    memset(context, 0, sizeof(*context));
    memcpy(context->state, initial, sizeof(initial));
}

static void arc_sha256_update(ArcSha256 *context,
                              const unsigned char *bytes,
                              size_t length)
{
    while (length > 0u) {
        size_t available = sizeof(context->block) - context->block_length;
        size_t amount = length < available ? length : available;

        memcpy(context->block + context->block_length, bytes, amount);
        context->block_length += amount;
        context->total_bytes += (uint64_t)amount;
        bytes += amount;
        length -= amount;
        if (context->block_length == sizeof(context->block)) {
            arc_sha256_transform(context, context->block);
            context->block_length = 0u;
        }
    }
}

static void arc_sha256_final(ArcSha256 *context, unsigned char digest[32])
{
    uint64_t total_bits = context->total_bytes * UINT64_C(8);
    size_t index;

    context->block[context->block_length++] = 0x80u;
    if (context->block_length > 56u) {
        memset(context->block + context->block_length, 0,
               sizeof(context->block) - context->block_length);
        arc_sha256_transform(context, context->block);
        context->block_length = 0u;
    }
    memset(context->block + context->block_length, 0,
           56u - context->block_length);
    arc_write_u64(context->block + 56u, total_bits);
    arc_sha256_transform(context, context->block);

    for (index = 0u; index < 8u; ++index) {
        uint32_t value = context->state[index];
        digest[(index * 4u)] = (unsigned char)(value >> 24);
        digest[(index * 4u) + 1u] = (unsigned char)(value >> 16);
        digest[(index * 4u) + 2u] = (unsigned char)(value >> 8);
        digest[(index * 4u) + 3u] = (unsigned char)value;
    }
    memset(context, 0, sizeof(*context));
}

static void arc_sha256(const unsigned char *bytes,
                       size_t length,
                       unsigned char digest[32])
{
    ArcSha256 context;

    arc_sha256_init(&context);
    arc_sha256_update(&context, bytes, length);
    arc_sha256_final(&context, digest);
}

static int arc_digest_equal(const unsigned char left[32],
                            const unsigned char right[32])
{
    unsigned int difference = 0u;
    size_t index;

    for (index = 0u; index < 32u; ++index) {
        difference |= (unsigned int)(left[index] ^ right[index]);
    }
    return difference == 0u;
}

static int arc_range_valid(const void *pointer, size_t length)
{
    uintptr_t start;

    if (length == 0u) {
        return 1;
    }
    if (pointer == NULL) {
        return 0;
    }
    start = (uintptr_t)pointer;
    return length - 1u <= UINTPTR_MAX - start;
}

static int arc_ranges_overlap(const void *left,
                              size_t left_length,
                              const void *right,
                              size_t right_length)
{
    uintptr_t left_start;
    uintptr_t right_start;

    if (left_length == 0u || right_length == 0u) {
        return 0;
    }
    if (!arc_range_valid(left, left_length) ||
        !arc_range_valid(right, right_length)) {
        return 1;
    }
    left_start = (uintptr_t)left;
    right_start = (uintptr_t)right;
    return left_start <= right_start + right_length - 1u &&
           right_start <= left_start + left_length - 1u;
}

static int arc_is_zero(const unsigned char *bytes, size_t length)
{
    size_t index;

    for (index = 0u; index < length; ++index) {
        if (bytes[index] != 0u) {
            return 0;
        }
    }
    return 1;
}

static int arc_name_valid(const unsigned char *name, size_t length)
{
    size_t index;
    size_t segment_start = 0u;

    if (length == 0u || length > 96u || name[0] == '/' ||
        name[length - 1u] == '/') {
        return 0;
    }
    for (index = 0u; index < length; ++index) {
        unsigned char byte = name[index];
        int allowed = (byte >= 'a' && byte <= 'z') ||
                      (byte >= '0' && byte <= '9') || byte == '-' ||
                      byte == '_' || byte == '.' || byte == '/';

        if (!allowed || byte == '\\' || byte == ':') {
            return 0;
        }
        if (byte == '/') {
            size_t segment_length = index - segment_start;
            if (segment_length == 0u || name[segment_start] == '.' ||
                (segment_length == 1u && name[segment_start] == '.') ||
                (segment_length == 2u && name[segment_start] == '.' &&
                 name[segment_start + 1u] == '.')) {
                return 0;
            }
            segment_start = index + 1u;
        }
    }
    if (name[segment_start] == '.') {
        return 0;
    }
    if (length < 4u || memcmp(name + length - 4u, ".txt", 4u) != 0) {
        return 0;
    }
    return 1;
}

static int arc_name_compare(const unsigned char *left,
                            size_t left_length,
                            const unsigned char *right,
                            size_t right_length)
{
    size_t common = left_length < right_length ? left_length : right_length;
    int result = memcmp(left, right, common);

    if (result != 0) {
        return result;
    }
    if (left_length < right_length) {
        return -1;
    }
    if (left_length > right_length) {
        return 1;
    }
    return 0;
}

static const ArcProfileMember *arc_profile_lookup(const unsigned char *name,
                                                  size_t length)
{
    size_t index;

    for (index = 0u;
         index < sizeof(arc_profile_members) / sizeof(arc_profile_members[0]);
         ++index) {
        size_t expected_length = strlen(arc_profile_members[index].name);
        if (length == expected_length &&
            memcmp(name, arc_profile_members[index].name, length) == 0) {
            return &arc_profile_members[index];
        }
    }
    return NULL;
}

static int arc_text_valid(const unsigned char *bytes, size_t length)
{
    size_t index = 0u;

    if (length == 0u || bytes[length - 1u] != '\n') {
        return 0;
    }
    if (length >= 3u && bytes[0] == 0xefu && bytes[1] == 0xbbu &&
        bytes[2] == 0xbfu) {
        return 0;
    }
    while (index < length) {
        unsigned char first = bytes[index];

        if (first < 0x80u) {
            if (first < 0x20u && first != '\t' && first != '\n') {
                return 0;
            }
            ++index;
        } else if (first >= 0xc2u && first <= 0xdfu) {
            if (index + 1u >= length || bytes[index + 1u] < 0x80u ||
                bytes[index + 1u] > 0xbfu) {
                return 0;
            }
            index += 2u;
        } else if (first == 0xe0u) {
            if (index + 2u >= length || bytes[index + 1u] < 0xa0u ||
                bytes[index + 1u] > 0xbfu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu) {
                return 0;
            }
            index += 3u;
        } else if ((first >= 0xe1u && first <= 0xecu) ||
                   (first >= 0xeeu && first <= 0xefu)) {
            if (index + 2u >= length || bytes[index + 1u] < 0x80u ||
                bytes[index + 1u] > 0xbfu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu) {
                return 0;
            }
            index += 3u;
        } else if (first == 0xedu) {
            if (index + 2u >= length || bytes[index + 1u] < 0x80u ||
                bytes[index + 1u] > 0x9fu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu) {
                return 0;
            }
            index += 3u;
        } else if (first == 0xf0u) {
            if (index + 3u >= length || bytes[index + 1u] < 0x90u ||
                bytes[index + 1u] > 0xbfu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu || bytes[index + 3u] < 0x80u ||
                bytes[index + 3u] > 0xbfu) {
                return 0;
            }
            index += 4u;
        } else if (first >= 0xf1u && first <= 0xf3u) {
            if (index + 3u >= length || bytes[index + 1u] < 0x80u ||
                bytes[index + 1u] > 0xbfu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu || bytes[index + 3u] < 0x80u ||
                bytes[index + 3u] > 0xbfu) {
                return 0;
            }
            index += 4u;
        } else if (first == 0xf4u) {
            if (index + 3u >= length || bytes[index + 1u] < 0x80u ||
                bytes[index + 1u] > 0x8fu || bytes[index + 2u] < 0x80u ||
                bytes[index + 2u] > 0xbfu || bytes[index + 3u] < 0x80u ||
                bytes[index + 3u] > 0xbfu) {
                return 0;
            }
            index += 4u;
        } else {
            return 0;
        }
    }
    return 1;
}

static int arc_knowledge_load(const ArcKnowledge *knowledge,
                              ArcKnowledge *state)
{
    if (knowledge == NULL || state == NULL ||
        ((uintptr_t)knowledge % _Alignof(max_align_t)) != 0u) {
        return 0;
    }
    memcpy(state, (const unsigned char *)(const void *)knowledge,
           sizeof(*state));
    return state->magic == ARC_KNOWLEDGE_MAGIC &&
           state->self == knowledge && state->source != NULL &&
           state->source_length > 0u &&
           state->source_length <= ARC_KNOWLEDGE_MAX_BYTES &&
           arc_range_valid(state->source, state->source_length);
}

static int arc_output_safe(const ArcKnowledge *knowledge,
                           const ArcKnowledge *state,
                           const void *output,
                           size_t output_length)
{
    return arc_range_valid(output, output_length) &&
           !arc_ranges_overlap(output, output_length,
                               state->source, state->source_length) &&
           !arc_ranges_overlap(output, output_length,
                               knowledge, ARC_KNOWLEDGE_WORKSPACE_BYTES);
}

ArcKnowledgeStatus arc_knowledge_open(
    const unsigned char *bytes,
    size_t length,
    const unsigned char expected_sha256[32],
    ArcKnowledgeStorage *storage,
    ArcKnowledge **out_knowledge)
{
    ArcKnowledge candidate;
    unsigned char actual_sha256[32];
    unsigned char expected_copy[32];
    unsigned char seen[ARC_KNOWLEDGE_MEMBER_COUNT];
    uint32_t member_count;
    uint64_t directory_length;
    uint64_t payload_offset;
    uint64_t expected_payload;
    size_t index;
    int unknown_member = 0;

    if (bytes == NULL || expected_sha256 == NULL || storage == NULL ||
        out_knowledge == NULL || length < 1u ||
        length > ARC_KNOWLEDGE_MAX_BYTES ||
        ((uintptr_t)storage % _Alignof(ArcKnowledgeStorage)) != 0u ||
        !arc_range_valid(bytes, length) ||
        !arc_range_valid(expected_sha256, 32u) ||
        !arc_range_valid(storage, sizeof(*storage)) ||
        !arc_range_valid(out_knowledge, sizeof(*out_knowledge)) ||
        arc_ranges_overlap(bytes, length, storage, sizeof(*storage)) ||
        arc_ranges_overlap(bytes, length,
                           out_knowledge, sizeof(*out_knowledge)) ||
        arc_ranges_overlap(expected_sha256, 32u,
                           out_knowledge, sizeof(*out_knowledge)) ||
        arc_ranges_overlap(storage, sizeof(*storage),
                           out_knowledge, sizeof(*out_knowledge))) {
        return ARC_KNOWLEDGE_INVALID_ARGUMENT;
    }
    *out_knowledge = NULL;
    memcpy(expected_copy, expected_sha256, sizeof(expected_copy));
    memset(storage, 0, sizeof(*storage));

    arc_sha256(bytes, length, actual_sha256);
    if (!arc_digest_equal(actual_sha256, expected_copy)) {
        return ARC_KNOWLEDGE_DIGEST_MISMATCH;
    }
    if (length < ARC_KNOWLEDGE_HEADER_BYTES ||
        memcmp(bytes, "ARCKB001", 8u) != 0 ||
        arc_read_u32(bytes + 8u) != 1u ||
        arc_read_u32(bytes + 12u) != 1u) {
        return ARC_KNOWLEDGE_INVALID_CONTAINER;
    }

    member_count = arc_read_u32(bytes + 16u);
    if ((member_count != 18u && member_count != 19u) ||
        member_count > ARC_KNOWLEDGE_MAX_MEMBERS ||
        arc_read_u32(bytes + 20u) != ARC_KNOWLEDGE_ENTRY_BYTES ||
        arc_read_u64(bytes + 24u) != ARC_KNOWLEDGE_HEADER_BYTES) {
        return ARC_KNOWLEDGE_INVALID_CONTAINER;
    }
    directory_length = (uint64_t)member_count * ARC_KNOWLEDGE_ENTRY_BYTES;
    payload_offset = ARC_KNOWLEDGE_HEADER_BYTES + directory_length;
    if (arc_read_u64(bytes + 32u) != directory_length ||
        arc_read_u64(bytes + 40u) != payload_offset ||
        arc_read_u64(bytes + 48u) != (uint64_t)length ||
        arc_read_u64(bytes + 56u) != 0u || payload_offset > length) {
        return ARC_KNOWLEDGE_INVALID_CONTAINER;
    }

    memset(&candidate, 0, sizeof(candidate));
    memset(seen, 0, sizeof(seen));
    expected_payload = payload_offset;

    for (index = 0u; index < member_count; ++index) {
        const unsigned char *entry = bytes + ARC_KNOWLEDGE_HEADER_BYTES +
                                     (index * ARC_KNOWLEDGE_ENTRY_BYTES);
        uint16_t name_length = arc_read_u16(entry);
        unsigned char required = entry[2];
        const unsigned char *name = entry + 56u;
        uint64_t member_offset = arc_read_u64(entry + 8u);
        uint64_t member_length = arc_read_u64(entry + 16u);
        const ArcProfileMember *profile;

        if (name_length < 1u || name_length > 96u || required > 1u ||
            entry[3] != 1u || !arc_is_zero(entry + 4u, 4u) ||
            !arc_is_zero(entry + 56u + name_length, 96u - name_length) ||
            !arc_is_zero(entry + 152u, 8u) ||
            !arc_name_valid(name, name_length) ||
            member_length < 1u ||
            member_length > ARC_KNOWLEDGE_MAX_MEMBER_BYTES ||
            member_offset != expected_payload || member_offset > length ||
            member_length > (uint64_t)length - member_offset) {
            return ARC_KNOWLEDGE_INVALID_CONTAINER;
        }
        if (index > 0u) {
            const unsigned char *previous = entry - ARC_KNOWLEDGE_ENTRY_BYTES;
            uint16_t previous_length = arc_read_u16(previous);
            if (arc_name_compare(previous + 56u, previous_length,
                                 name, name_length) >= 0) {
                return ARC_KNOWLEDGE_INVALID_CONTAINER;
            }
        }
        expected_payload = member_offset + member_length;
        profile = arc_profile_lookup(name, name_length);
        if (profile == NULL) {
            unknown_member = 1;
            continue;
        }
        if (profile->required != required || seen[profile->member] != 0u) {
            return ARC_KNOWLEDGE_INVALID_CONTAINER;
        }
        seen[profile->member] = 1u;
        candidate.members[profile->member].offset = (size_t)member_offset;
        candidate.members[profile->member].length = (size_t)member_length;
        memcpy(candidate.members[profile->member].sha256, entry + 24u, 32u);
        candidate.members[profile->member].state = 1u;
    }
    if (expected_payload != (uint64_t)length) {
        return ARC_KNOWLEDGE_INVALID_CONTAINER;
    }
    for (index = 0u; index < ARC_KNOWLEDGE_RELEASE_NOTES; ++index) {
        if (seen[index] == 0u) {
            return ARC_KNOWLEDGE_MISSING_ESSENTIAL;
        }
    }
    if (unknown_member ||
        (member_count == 19u && seen[ARC_KNOWLEDGE_RELEASE_NOTES] == 0u) ||
        (member_count == 18u && seen[ARC_KNOWLEDGE_RELEASE_NOTES] != 0u)) {
        return ARC_KNOWLEDGE_INVALID_CONTAINER;
    }

    for (index = 0u; index < ARC_KNOWLEDGE_MEMBER_COUNT; ++index) {
        ArcKnowledgeSlot *slot = &candidate.members[index];
        unsigned char member_sha256[32];
        int valid_digest;
        int valid_text;

        if (slot->state == 0u) {
            continue;
        }
        arc_sha256(bytes + slot->offset, slot->length, member_sha256);
        valid_digest = arc_digest_equal(member_sha256, slot->sha256);
        valid_text = arc_text_valid(bytes + slot->offset, slot->length);
        if (!valid_digest || !valid_text) {
            if (index == ARC_KNOWLEDGE_RELEASE_NOTES) {
                memset(slot, 0, sizeof(*slot));
                slot->state = 2u;
            } else {
                return ARC_KNOWLEDGE_INVALID_CONTAINER;
            }
        }
    }

    candidate.magic = ARC_KNOWLEDGE_MAGIC;
    candidate.self = (const ArcKnowledge *)storage;
    candidate.source = bytes;
    candidate.source_length = length;
    memcpy(candidate.source_sha256, actual_sha256, sizeof(actual_sha256));
    memcpy(storage->bytes, &candidate, sizeof(candidate));
    *out_knowledge = (ArcKnowledge *)storage;
    memset(&candidate, 0, sizeof(candidate));
    memset(actual_sha256, 0, sizeof(actual_sha256));
    return ARC_KNOWLEDGE_OK;
}

ArcKnowledgeStatus arc_knowledge_info(
    const ArcKnowledge *knowledge,
    ArcKnowledgeMember member,
    size_t *out_length,
    unsigned char out_sha256[32])
{
    ArcKnowledge state;
    const ArcKnowledgeSlot *slot;

    if (!arc_knowledge_load(knowledge, &state) ||
        member < ARC_KNOWLEDGE_SPEC_000 ||
        member > ARC_KNOWLEDGE_RELEASE_NOTES || out_length == NULL ||
        out_sha256 == NULL ||
        !arc_output_safe(knowledge, &state, out_length, sizeof(*out_length)) ||
        !arc_output_safe(knowledge, &state, out_sha256, 32u) ||
        arc_ranges_overlap(out_length, sizeof(*out_length), out_sha256, 32u)) {
        return ARC_KNOWLEDGE_INVALID_ARGUMENT;
    }
    *out_length = 0u;
    memset(out_sha256, 0, 32u);
    slot = &state.members[member];
    if (slot->state != 1u) {
        return ARC_KNOWLEDGE_OMITTED;
    }
    *out_length = slot->length;
    memcpy(out_sha256, slot->sha256, 32u);
    return ARC_KNOWLEDGE_OK;
}

ArcKnowledgeStatus arc_knowledge_read_text(
    const ArcKnowledge *knowledge,
    ArcKnowledgeMember member,
    size_t offset,
    unsigned char *destination,
    size_t destination_capacity,
    size_t *out_written,
    int *out_done)
{
    ArcKnowledge state;
    const ArcKnowledgeSlot *slot;
    size_t remaining;
    size_t amount;

    if (!arc_knowledge_load(knowledge, &state) ||
        member < ARC_KNOWLEDGE_SPEC_000 ||
        member > ARC_KNOWLEDGE_RELEASE_NOTES || out_written == NULL ||
        out_done == NULL ||
        !arc_output_safe(knowledge, &state,
                         out_written, sizeof(*out_written)) ||
        !arc_output_safe(knowledge, &state, out_done, sizeof(*out_done)) ||
        arc_ranges_overlap(out_written, sizeof(*out_written),
                           out_done, sizeof(*out_done)) ||
        (destination_capacity > 0u && destination == NULL) ||
        (destination_capacity > 0u &&
         !arc_output_safe(knowledge, &state,
                          destination, destination_capacity)) ||
        (destination_capacity > 0u &&
         (arc_ranges_overlap(destination, destination_capacity,
                             out_written, sizeof(*out_written)) ||
          arc_ranges_overlap(destination, destination_capacity,
                             out_done, sizeof(*out_done))))) {
        return ARC_KNOWLEDGE_INVALID_ARGUMENT;
    }
    *out_written = 0u;
    *out_done = 0;
    slot = &state.members[member];
    if (slot->state != 1u) {
        return ARC_KNOWLEDGE_OMITTED;
    }
    if (offset > slot->length) {
        return ARC_KNOWLEDGE_OUT_OF_RANGE;
    }
    remaining = slot->length - offset;
    if (remaining == 0u) {
        *out_done = 1;
        return ARC_KNOWLEDGE_OK;
    }
    if (destination_capacity == 0u) {
        return ARC_KNOWLEDGE_BUFFER_TOO_SMALL;
    }
    amount = remaining < destination_capacity ? remaining : destination_capacity;
    memcpy(destination, state.source + slot->offset + offset, amount);
    *out_written = amount;
    *out_done = amount == remaining ? 1 : 0;
    return ARC_KNOWLEDGE_OK;
}

void arc_knowledge_close(ArcKnowledgeStorage *storage)
{
    volatile unsigned char *bytes;
    size_t index;

    if (storage == NULL ||
        ((uintptr_t)storage % _Alignof(ArcKnowledgeStorage)) != 0u) {
        return;
    }
    bytes = storage->bytes;
    for (index = 0u; index < sizeof(*storage); ++index) {
        bytes[index] = 0u;
    }
}
