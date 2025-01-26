const express = require('express');
const os = require('os');
const app = express();

app.use(express.json());

// Complex regex pattern for text analysis
const EMAIL_PATTERN = /^(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9]))\.){3}(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9])|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])/;

app.post('/analyze', (req, res) => {
    const { text } = req.body;
   
    if (!text) {
        return res.status(400).json({ error: 'Text is required' });
    }

    const startTime = process.hrtime();

    // Perform intensive regex operations
    const words = text.split(/\s+/);
    const emails = words.filter(word => EMAIL_PATTERN.test(word));
   
    // Additional text analysis
    const wordFrequency = words.reduce((acc, word) => {
        acc[word] = (acc[word] || 0) + 1;
        return acc;
    }, {});

    const endTime = process.hrtime(startTime);
    const timeMs = (endTime[0] * 1000 + endTime[1] / 1000000).toFixed(2);

    res.json({
        architecture: process.arch,
        wordCount: words.length,
        emails: emails,
        wordFrequency: wordFrequency,
        processingTime: `${timeMs}ms`
    });
});

const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT} (Architecture: ${process.arch})`);
});
