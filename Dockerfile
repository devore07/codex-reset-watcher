FROM swift:6.3.3
WORKDIR /workspace
COPY Package.swift ./
COPY Sources/ClaudeUsageCore Sources/ClaudeUsageCore
COPY Sources/ClaudeUsageBridge Sources/ClaudeUsageBridge
COPY Tests/ClaudeUsageCoreTests Tests/ClaudeUsageCoreTests
RUN swift build --product ClaudeUsageBridge --jobs 1
CMD ["swift", "test", "--jobs", "1"]
