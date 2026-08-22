#ifndef ARC_KNOWLEDGE_H
#define ARC_KNOWLEDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ARC_KNOWLEDGE_MAX_MEMBERS 32u
#define ARC_KNOWLEDGE_WORKSPACE_BYTES 16384u

typedef union ArcKnowledgeStorage {
    max_align_t alignment;
    unsigned char bytes[ARC_KNOWLEDGE_WORKSPACE_BYTES];
} ArcKnowledgeStorage;

typedef struct ArcKnowledge ArcKnowledge;

typedef enum ArcKnowledgeStatus {
    ARC_KNOWLEDGE_OK = 0,
    ARC_KNOWLEDGE_INVALID_ARGUMENT,
    ARC_KNOWLEDGE_DIGEST_MISMATCH,
    ARC_KNOWLEDGE_INVALID_CONTAINER,
    ARC_KNOWLEDGE_MISSING_ESSENTIAL,
    ARC_KNOWLEDGE_OMITTED,
    ARC_KNOWLEDGE_OUT_OF_RANGE,
    ARC_KNOWLEDGE_BUFFER_TOO_SMALL
} ArcKnowledgeStatus;

typedef enum ArcKnowledgeMember {
    ARC_KNOWLEDGE_SPEC_000 = 0,
    ARC_KNOWLEDGE_SPEC_001,
    ARC_KNOWLEDGE_SPEC_002,
    ARC_KNOWLEDGE_SPEC_003,
    ARC_KNOWLEDGE_SPEC_004,
    ARC_KNOWLEDGE_SPEC_005,
    ARC_KNOWLEDGE_SPEC_006,
    ARC_KNOWLEDGE_SPEC_007,
    ARC_KNOWLEDGE_SPEC_008,
    ARC_KNOWLEDGE_SPEC_009,
    ARC_KNOWLEDGE_SPEC_010,
    ARC_KNOWLEDGE_SPEC_011,
    ARC_KNOWLEDGE_SPEC_012,
    ARC_KNOWLEDGE_AI_GUIDE,
    ARC_KNOWLEDGE_HELP,
    ARC_KNOWLEDGE_MAN_PAGE,
    ARC_KNOWLEDGE_LICENSE,
    ARC_KNOWLEDGE_NOTICE,
    ARC_KNOWLEDGE_RELEASE_NOTES
} ArcKnowledgeMember;

/** Compute a SHA-256 digest using ARC's bundled, dependency-free implementation. */
void arc_knowledge_sha256(
    const unsigned char *bytes,
    size_t length,
    unsigned char out_digest[32]);

ArcKnowledgeStatus arc_knowledge_open(
    const unsigned char *bytes,
    size_t length,
    const unsigned char expected_sha256[32],
    ArcKnowledgeStorage *storage,
    ArcKnowledge **out_knowledge);

ArcKnowledgeStatus arc_knowledge_info(
    const ArcKnowledge *knowledge,
    ArcKnowledgeMember member,
    size_t *out_length,
    unsigned char out_sha256[32]);

ArcKnowledgeStatus arc_knowledge_read_text(
    const ArcKnowledge *knowledge,
    ArcKnowledgeMember member,
    size_t offset,
    unsigned char *destination,
    size_t destination_capacity,
    size_t *out_written,
    int *out_done);

void arc_knowledge_close(ArcKnowledgeStorage *storage);

#ifdef __cplusplus
}
#endif

#endif
