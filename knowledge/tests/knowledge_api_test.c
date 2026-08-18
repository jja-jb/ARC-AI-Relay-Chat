#include "arc_knowledge.h"

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_CONTAINER_BYTES 8388608u

static unsigned char source[MAX_CONTAINER_BYTES];

static int hex_digit(char character)
{
    if (character >= '0' && character <= '9') {
        return character - '0';
    }
    if (character >= 'a' && character <= 'f') {
        return character - 'a' + 10;
    }
    return -1;
}

static int decode_digest(const char *text, unsigned char digest[32])
{
    size_t index;

    for (index = 0u; index < 32u; ++index) {
        int upper = hex_digit(text[index * 2u]);
        int lower = hex_digit(text[(index * 2u) + 1u]);
        if (upper < 0 || lower < 0) {
            return 0;
        }
        digest[index] = (unsigned char)((upper << 4) | lower);
    }
    return text[64] == '\0';
}

static int load(const char *path, size_t *out_length)
{
    struct stat metadata;
    size_t total = 0u;
    int descriptor = open(path, O_RDONLY | O_NOFOLLOW);

    if (descriptor < 0 || fstat(descriptor, &metadata) != 0 ||
        !S_ISREG(metadata.st_mode) || metadata.st_size < 1 ||
        metadata.st_size > (off_t)MAX_CONTAINER_BYTES) {
        if (descriptor >= 0) {
            close(descriptor);
        }
        return 0;
    }
    while (total < (size_t)metadata.st_size) {
        ssize_t amount = read(descriptor, source + total,
                              (size_t)metadata.st_size - total);
        if (amount <= 0) {
            close(descriptor);
            return 0;
        }
        total += (size_t)amount;
    }
    if (close(descriptor) != 0) {
        return 0;
    }
    *out_length = total;
    return 1;
}

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "check failed at line %d\n", __LINE__); \
        return 1; \
    } \
} while (0)

int main(int argc, char **argv)
{
    ArcKnowledgeStorage storage;
    ArcKnowledgeStorage second_storage;
    ArcKnowledge *knowledge = NULL;
    unsigned char expected[32];
    unsigned char wrong[32];
    unsigned char member_digest[32];
    unsigned char buffer[31];
    size_t source_length;
    size_t member_length;
    size_t written;
    int done;
    int member;

    CHECK(argc == 3);
    CHECK(sizeof(storage) == ARC_KNOWLEDGE_WORKSPACE_BYTES);
    CHECK(decode_digest(argv[2], expected));
    CHECK(load(argv[1], &source_length));
    CHECK(arc_knowledge_open(source, 0u, expected, &storage,
                             &knowledge) == ARC_KNOWLEDGE_INVALID_ARGUMENT);
    CHECK(arc_knowledge_open(source, MAX_CONTAINER_BYTES + 1u, expected,
                             &storage, &knowledge) ==
          ARC_KNOWLEDGE_INVALID_ARGUMENT);

    memcpy(wrong, expected, sizeof(wrong));
    wrong[0] ^= 1u;
    memset(&storage, 0xa5, sizeof(storage));
    CHECK(arc_knowledge_open(source, source_length, wrong, &storage,
                             &knowledge) == ARC_KNOWLEDGE_DIGEST_MISMATCH);
    CHECK(knowledge == NULL);
    for (member = 0; member < (int)sizeof(storage.bytes); ++member) {
        CHECK(storage.bytes[member] == 0u);
    }
    CHECK(arc_knowledge_open(
              source, source_length, expected, &second_storage,
              (ArcKnowledge **)(void *)second_storage.bytes) ==
          ARC_KNOWLEDGE_INVALID_ARGUMENT);

    CHECK(arc_knowledge_open(source, source_length, expected, &storage,
                             &knowledge) == ARC_KNOWLEDGE_OK);
    CHECK(knowledge != NULL);
    for (member = ARC_KNOWLEDGE_SPEC_000;
         member <= ARC_KNOWLEDGE_NOTICE; ++member) {
        size_t offset = 0u;
        CHECK(arc_knowledge_info(knowledge, (ArcKnowledgeMember)member,
                                 &member_length, member_digest) ==
              ARC_KNOWLEDGE_OK);
        CHECK(member_length > 0u);
        while (offset < member_length) {
            CHECK(arc_knowledge_read_text(
                      knowledge, (ArcKnowledgeMember)member, offset,
                      buffer, sizeof(buffer), &written, &done) ==
                  ARC_KNOWLEDGE_OK);
            CHECK(written > 0u && written <= sizeof(buffer));
            offset += written;
            CHECK(done == (offset == member_length));
        }
        CHECK(arc_knowledge_read_text(
                  knowledge, (ArcKnowledgeMember)member, member_length,
                  NULL, 0u, &written, &done) == ARC_KNOWLEDGE_OK);
        CHECK(written == 0u && done == 1);
        CHECK(arc_knowledge_read_text(
                  knowledge, (ArcKnowledgeMember)member, member_length + 1u,
                  buffer, sizeof(buffer), &written, &done) ==
              ARC_KNOWLEDGE_OUT_OF_RANGE);
        CHECK(arc_knowledge_read_text(
                  knowledge, (ArcKnowledgeMember)member, 0u,
                  NULL, 0u, &written, &done) ==
              ARC_KNOWLEDGE_BUFFER_TOO_SMALL);
    }
    CHECK(arc_knowledge_info(knowledge, ARC_KNOWLEDGE_RELEASE_NOTES,
                             &member_length, member_digest) ==
          ARC_KNOWLEDGE_OMITTED);
    CHECK(member_length == 0u);
    CHECK(arc_knowledge_read_text(
              knowledge, ARC_KNOWLEDGE_SPEC_000, 0u,
              source, sizeof(buffer), &written, &done) ==
          ARC_KNOWLEDGE_INVALID_ARGUMENT);
    CHECK(arc_knowledge_read_text(
              knowledge, ARC_KNOWLEDGE_SPEC_000, 0u,
              buffer, sizeof(buffer), (size_t *)(void *)source, &done) ==
          ARC_KNOWLEDGE_INVALID_ARGUMENT);
    CHECK(arc_knowledge_info(
              knowledge, ARC_KNOWLEDGE_SPEC_000, &member_length,
              storage.bytes) == ARC_KNOWLEDGE_INVALID_ARGUMENT);

    arc_knowledge_close(&storage);
    CHECK(arc_knowledge_info(knowledge, ARC_KNOWLEDGE_SPEC_000,
                             &member_length, member_digest) ==
          ARC_KNOWLEDGE_INVALID_ARGUMENT);
    for (member = 0; member < (int)sizeof(storage.bytes); ++member) {
        CHECK(storage.bytes[member] == 0u);
    }
    puts("knowledge API checks passed");
    return 0;
}
