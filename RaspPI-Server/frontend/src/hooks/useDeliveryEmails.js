export function getDeliveries(emails) {
    const keywords = [
        "package",
        "delivery",
        "delivered",
        "shipped",
        "shipping",
        "tracking",
        "out for delivery",
        "arriving"
    ];

    return emails.filter(email => { const content = `${email.subject ?? ""} ${email.summary ?? ""}`.toLowerCase();

        return keywords.some(keyword => content.includes(keyword));
    });
}