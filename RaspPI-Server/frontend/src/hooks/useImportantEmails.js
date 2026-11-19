export function getImportantEmails(emails) {
    return emails.filter(email =>
        email.importance === "high"
    );
}