export function getTodayEvents(emails) {
    const today = new Date().toLocaleDateString("en-CA");

    return emails.filter(email => {
        if (!email.due) return false;

        const dueDate = email.due.slice(0, 10);

        return dueDate === today;
    });
}