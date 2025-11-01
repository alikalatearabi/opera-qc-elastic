import moment from 'moment-jalaali';

/**
 * Converts a Persian (Jalaali) date string to a JavaScript Date object
 * Supports multiple input formats:
 * - ISO format: "1404-07-22T10:00:00.000Z"
 * - Standard format: "1404-07-22 14:30:00"
 * 
 * @param persianDate - Persian date string in various formats
 * @returns Converted JavaScript Date object
 */
export const convertPersianToGregorian = (persianDate: string): Date => {
    if (persianDate.includes('T') && persianDate.includes('Z')) {
        // ISO format like "1404-07-22T10:00:00.000Z" - treat as Persian date
        const dateOnly = persianDate.split('T')[0]; // Extract YYYY-MM-DD part
        const [year, month, day] = dateOnly.split('-').map(Number);
        const persianMoment = moment(`${year}-${month}-${day}`, 'jYYYY-jM-jD');
        const gregorianDate = persianMoment.toDate();
        console.log(`Converted Persian ISO date ${persianDate} to Gregorian: ${gregorianDate.toISOString()}`);
        return gregorianDate;
    } else {
        // Original format: Persian YYYY-MM-DD HH:mm:ss
        const [persianDatePart, timePart] = persianDate.split(' ');
        const [year, month, day] = persianDatePart.split('-').map(Number);
        const persianMoment = moment(`${year}-${month}-${day} ${timePart}`, 'jYYYY-jM-jD HH:mm:ss');
        const gregorianDate = persianMoment.toDate();
        console.log(`Converted Persian date ${persianDate} to Gregorian: ${gregorianDate.toISOString()}`);
        return gregorianDate;
    }
};
