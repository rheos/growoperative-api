-- MySQL dump 10.13  Distrib 5.7.44, for Linux (x86_64)
--
-- Host: localhost    Database: growoperative_development
-- ------------------------------------------------------
-- Server version	5.7.44

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `ar_internal_metadata`
--

DROP TABLE IF EXISTS `ar_internal_metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ar_internal_metadata` (
  `key` varchar(255) CHARACTER SET utf8 COLLATE utf8_unicode_ci NOT NULL,
  `value` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ar_internal_metadata`
--

LOCK TABLES `ar_internal_metadata` WRITE;
/*!40000 ALTER TABLE `ar_internal_metadata` DISABLE KEYS */;
INSERT INTO `ar_internal_metadata` VALUES ('environment','development','2025-06-17 17:28:13','2026-04-08 05:45:48');
/*!40000 ALTER TABLE `ar_internal_metadata` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `categories`
--

DROP TABLE IF EXISTS `categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `categories` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `category_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `default_unit` int(11) DEFAULT NULL,
  `default_consumer_unit` int(11) DEFAULT NULL,
  `default_node_price` decimal(10,2) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `price` decimal(10,0) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `categories`
--

LOCK TABLES `categories` WRITE;
/*!40000 ALTER TABLE `categories` DISABLE KEYS */;
INSERT INTO `categories` VALUES (1,'herbs and greens',1,2,1.00,'2025-06-18 01:07:49','2025-06-18 01:07:49',NULL),(2,'tinctures',3,4,1.00,'2025-06-18 01:07:49','2025-06-18 01:07:49',NULL);
/*!40000 ALTER TABLE `categories` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `category_sizes`
--

DROP TABLE IF EXISTS `category_sizes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `category_sizes` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `category_id` int(11) NOT NULL,
  `item_unit_id` int(11) NOT NULL,
  `quantity` float DEFAULT NULL,
  `price` float DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `category_sizes`
--

LOCK TABLES `category_sizes` WRITE;
/*!40000 ALTER TABLE `category_sizes` DISABLE KEYS */;
/*!40000 ALTER TABLE `category_sizes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `global_settings`
--

DROP TABLE IF EXISTS `global_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `global_settings` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `value` int(11) DEFAULT '3',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `setting` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `global_settings`
--

LOCK TABLES `global_settings` WRITE;
/*!40000 ALTER TABLE `global_settings` DISABLE KEYS */;
INSERT INTO `global_settings` VALUES (1,3,'2025-06-18 01:07:43','2025-06-18 01:07:43','ChainLimit'),(2,1,'2025-06-18 01:07:43','2025-06-18 01:07:43','user_category_relationship_price'),(3,4,'2025-06-18 01:07:43','2025-06-18 01:07:43','RangeDegree'),(4,0,'2026-04-10 17:05:56','2026-04-10 17:05:56','demo_setup_enabled');
/*!40000 ALTER TABLE `global_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `grades`
--

DROP TABLE IF EXISTS `grades`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `grades` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `value` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `grades`
--

LOCK TABLES `grades` WRITE;
/*!40000 ALTER TABLE `grades` DISABLE KEYS */;
INSERT INTO `grades` VALUES (1,'C','10','2025-06-18 01:07:50','2025-06-18 01:07:50'),(2,'B','20','2025-06-18 01:07:50','2025-06-18 01:07:50'),(3,'A','30','2025-06-18 01:07:50','2025-06-18 01:07:50'),(4,'AA','40','2025-06-18 01:07:50','2025-06-18 01:07:50'),(5,'AAA','50','2025-06-18 01:07:50','2025-06-18 01:07:50'),(6,'A+','60','2025-06-18 01:07:50','2025-06-18 01:07:50'),(7,'A++','70','2025-06-18 01:07:50','2025-06-18 01:07:50');
/*!40000 ALTER TABLE `grades` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `inventories`
--

DROP TABLE IF EXISTS `inventories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inventories` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `item_id` bigint(20) DEFAULT NULL,
  `quantity` float DEFAULT NULL,
  `price` decimal(10,0) DEFAULT NULL,
  `status` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `ref_id` int(11) DEFAULT NULL,
  `avatars` json DEFAULT NULL,
  `gallery_map` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT '---\n- "<-"\n- "<-"\n- "<-"\n- "<-"\n- "<-"\n',
  `ref_price` float DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`id`),
  KEY `index_inventories_on_user_id` (`user_id`),
  KEY `index_inventories_on_item_id` (`item_id`),
  CONSTRAINT `fk_rails_6642cbdd87` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_fcf6633a1e` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=584 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `inventories`
--

LOCK TABLES `inventories` WRITE;
/*!40000 ALTER TABLE `inventories` DISABLE KEYS */;
INSERT INTO `inventories` VALUES (528,7,14,4,4,1,'2026-04-12 05:49:48','2026-04-12 18:02:28',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(529,7,15,3,4,1,'2026-04-12 05:49:48','2026-04-12 18:03:18',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(530,1,4,5,4,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(531,12,18,3,4,1,'2026-04-12 05:49:48','2026-04-12 18:34:29',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(532,12,19,3,4,1,'2026-04-12 05:49:48','2026-04-12 16:43:04',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(533,3,7,3,4,1,'2026-04-12 05:49:48','2026-04-12 19:43:39',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(534,3,8,5,4,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(535,5,10,10,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(536,5,11,8,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(537,4,9,10,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(538,6,12,8,4,1,'2026-04-12 05:49:48','2026-04-12 06:19:21',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(539,6,13,5,6,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(540,10,16,11,5,1,'2026-04-12 05:49:48','2026-04-12 14:26:28',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(541,10,17,10,3,1,'2026-04-12 05:49:48','2026-04-12 15:09:25',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(542,7,11,2,4,1,'2026-04-12 05:49:48','2026-04-12 18:02:39',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,'Some very fine tomatoes'),(543,7,9,4,4,1,'2026-04-12 05:49:48','2026-04-12 06:36:04',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(544,1,14,4,4,1,'2026-04-12 05:49:48','2026-04-12 06:39:07',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(545,12,16,4,4,1,'2026-04-12 05:49:48','2026-04-12 18:33:36',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,'null'),(546,12,17,5,4,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(547,3,15,5,4,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(548,3,4,4,4,1,'2026-04-12 05:49:48','2026-04-12 18:12:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(549,5,19,9,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(550,5,7,8,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(551,4,18,9,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(552,6,8,6,4,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(553,6,10,5,6,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(554,10,12,13,5,1,'2026-04-12 05:49:48','2026-04-12 18:29:58',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,''),(555,10,13,15,3,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,'null'),(556,1,15,0,4,1,'2026-04-12 05:49:48','2026-04-12 06:38:57',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(558,3,18,1,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(559,3,19,1,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(560,3,8,2,4,1,'2026-04-12 05:49:48','2026-04-12 18:12:12',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',0,NULL),(563,10,17,0,3,2,'2026-04-12 05:54:45','2026-04-12 16:36:45',541,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(564,6,12,1,4,2,'2026-04-12 06:19:21','2026-04-12 06:19:21',538,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(565,7,9,1,4,2,'2026-04-12 06:36:03','2026-04-12 06:36:03',543,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(566,1,15,1,4,2,'2026-04-12 06:38:57','2026-04-12 06:38:57',556,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(567,1,14,1,4,2,'2026-04-12 06:39:07','2026-04-12 06:39:07',544,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(568,10,16,1,5,2,'2026-04-12 14:26:28','2026-04-12 14:26:28',540,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(569,10,12,5,5,2,'2026-04-12 14:26:38','2026-04-12 14:26:38',554,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(570,10,17,5,3,2,'2026-04-12 16:36:45','2026-04-12 16:36:45',563,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(571,12,19,2,4,2,'2026-04-12 16:43:04','2026-04-12 16:43:04',532,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(572,12,18,1,4,2,'2026-04-12 16:43:13','2026-04-12 16:43:13',531,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(573,7,14,1,4,2,'2026-04-12 18:02:28','2026-04-12 18:02:28',528,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(574,7,11,1,4,2,'2026-04-12 18:02:39','2026-04-12 18:02:39',542,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(575,7,15,0,4,2,'2026-04-12 18:03:18','2026-04-12 18:34:00',529,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(576,3,8,1,4,2,'2026-04-12 18:12:12','2026-04-12 18:12:12',560,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(577,3,4,1,4,2,'2026-04-12 18:12:48','2026-04-12 18:12:48',548,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(578,10,12,2,5,2,'2026-04-12 18:29:58','2026-04-12 18:29:58',554,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(579,12,16,2,4,2,'2026-04-12 18:33:36','2026-04-12 18:33:36',545,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(580,7,15,2,4,2,'2026-04-12 18:34:00','2026-04-12 18:34:00',575,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(581,12,18,2,4,2,'2026-04-12 18:34:29','2026-04-12 18:34:29',531,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(582,3,7,1,4,2,'2026-04-12 19:43:37','2026-04-12 19:43:37',533,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(583,3,7,2,4,2,'2026-04-12 19:43:39','2026-04-12 19:43:39',533,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL);
/*!40000 ALTER TABLE `inventories` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `invitations`
--

DROP TABLE IF EXISTS `invitations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `invitations` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `invitation_code` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_id` bigint(20) DEFAULT NULL,
  `status` int(11) DEFAULT NULL,
  `label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT '',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `user_type` int(11) DEFAULT '0',
  `note_label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `accepted_id` int(11) DEFAULT NULL,
  `user_price` float DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_invitations_on_user_id` (`user_id`),
  CONSTRAINT `fk_rails_7eae413fe6` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `invitations`
--

LOCK TABLES `invitations` WRITE;
/*!40000 ALTER TABLE `invitations` DISABLE KEYS */;
INSERT INTO `invitations` VALUES (1,'JZA7SNVP',1,1,'','2025-06-18 01:07:44','2025-06-18 01:07:44',1,NULL,2,NULL),(2,'G71N3T0S',1,1,'','2025-06-18 01:07:44','2025-06-18 01:07:45',2,NULL,3,NULL),(3,'MQJK3BG5',3,1,'','2025-06-18 01:07:45','2025-06-18 01:07:45',2,NULL,4,NULL),(4,'NJ2QPLW0',3,1,'','2025-06-18 01:07:45','2025-06-18 01:07:45',1,NULL,5,NULL),(5,'UZSGTY3V',3,1,'','2025-06-18 01:07:46','2025-06-18 01:07:46',2,NULL,6,NULL),(6,'H4KC2AJS',1,1,'','2025-06-18 01:07:46','2025-06-18 01:07:46',2,NULL,7,NULL),(7,'6DN58LU1',7,1,'','2025-06-18 01:07:46','2025-06-18 01:07:47',3,NULL,8,NULL),(8,'NMEZVDL0',8,1,'','2025-06-18 01:07:47','2025-06-18 01:07:47',0,NULL,9,NULL),(9,'I3U8KDJW',1,1,'','2025-06-18 01:07:47','2025-06-18 01:07:48',2,NULL,10,NULL),(10,'KGR7LN08',10,1,'','2025-06-18 01:07:48','2025-06-18 01:07:48',3,NULL,11,NULL),(11,'EDB2P85X',7,1,'','2025-06-18 01:07:48','2025-06-18 01:07:48',2,NULL,12,NULL),(12,'NXZ4LIA0',11,NULL,'','2025-06-18 01:07:49','2025-06-18 01:07:49',3,NULL,NULL,NULL),(13,'2J46IVHR',12,1,'','2025-06-18 01:07:49','2025-06-18 01:07:49',1,NULL,13,NULL),(14,'HJPWIL1R',1,0,'','2025-06-26 07:58:06','2025-06-26 07:58:06',0,NULL,NULL,NULL),(15,'2X4YQJRU',1,0,'','2025-06-26 07:58:20','2025-06-26 07:58:20',0,NULL,NULL,NULL),(16,'3D6UTGXJ',7,0,'buddy','2025-06-26 11:47:53','2025-06-26 12:00:00',2,NULL,NULL,2),(17,'9SIHLY0T',12,0,'buddy','2025-06-26 12:00:48','2025-06-26 12:30:27',2,NULL,NULL,1),(18,'SVMG1BA7',12,0,'','2025-06-26 12:30:44','2025-06-26 12:30:44',2,NULL,NULL,NULL),(19,'Z5S2TKNM',6,1,'','2026-04-12 18:39:16','2026-04-12 19:14:19',3,NULL,8,NULL),(20,'PHA0B9EJ',8,0,'','2026-04-12 18:43:08','2026-04-12 18:43:08',0,NULL,NULL,NULL),(21,'29ZDAJ6Q',6,0,'','2026-04-12 18:44:16','2026-04-12 18:44:16',3,NULL,NULL,NULL);
/*!40000 ALTER TABLE `invitations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `item_names`
--

DROP TABLE IF EXISTS `item_names`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `item_names` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `category_id` bigint(20) DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_item_names_on_category_id` (`category_id`),
  CONSTRAINT `fk_rails_7c76700650` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `item_names`
--

LOCK TABLES `item_names` WRITE;
/*!40000 ALTER TABLE `item_names` DISABLE KEYS */;
INSERT INTO `item_names` VALUES (1,'Black Krim Tomatoes',1,NULL,'2025-06-19 22:13:13','2025-06-19 22:13:13'),(2,'Black Krim',1,NULL,'2025-06-19 22:13:34','2025-06-19 22:13:34'),(3,'Arugula',1,NULL,'2025-06-22 07:02:34','2025-06-22 07:02:34'),(4,'Basil',1,NULL,'2025-06-22 08:36:47','2025-06-22 08:36:47'),(5,'Black Cherry Tomatoes',1,NULL,'2025-06-22 08:39:43','2025-06-22 08:39:43'),(6,'Black Cherry',1,NULL,'2025-06-22 08:40:27','2025-06-22 08:40:27'),(7,'Curly Kale',1,NULL,'2025-06-22 08:41:53','2025-06-22 08:41:53'),(8,'Early Girl',1,NULL,'2025-06-22 08:55:00','2025-06-22 08:55:00'),(9,'Cabbage',1,NULL,'2025-06-22 08:56:33','2025-06-22 08:56:33'),(10,'Fennel',1,NULL,'2025-06-22 08:58:56','2025-06-22 08:58:56'),(11,'Lemon Balm',1,NULL,'2025-06-22 09:00:13','2025-06-22 09:00:13'),(12,'Lettuce',1,NULL,'2025-06-22 09:01:51','2025-06-22 09:01:51'),(13,'Mint',1,NULL,'2025-06-22 09:35:20','2025-06-22 09:35:20'),(14,'Hot Peppers',1,NULL,'2025-06-22 09:36:48','2025-06-22 09:36:48'),(15,'Purple Cabbage',1,NULL,'2025-06-22 09:38:48','2025-06-22 09:38:48'),(16,'Russet Potatatoes',1,NULL,'2025-06-22 09:40:59','2025-06-22 09:40:59'),(17,'Russet Potatoes',1,NULL,'2025-06-22 09:41:36','2025-06-22 09:41:36'),(18,'Goji Berries',1,NULL,'2026-04-10 19:09:30','2026-04-10 19:09:30');
/*!40000 ALTER TABLE `item_names` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `item_relationships`
--

DROP TABLE IF EXISTS `item_relationships`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `item_relationships` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `item_id` bigint(20) DEFAULT NULL,
  `relationship_id` bigint(20) DEFAULT NULL,
  `status` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_item_relationships_on_item_id` (`item_id`),
  KEY `index_item_relationships_on_relationship_id` (`relationship_id`),
  CONSTRAINT `fk_rails_564e5c549e` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`),
  CONSTRAINT `fk_rails_998af430dd` FOREIGN KEY (`relationship_id`) REFERENCES `relationships` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `item_relationships`
--

LOCK TABLES `item_relationships` WRITE;
/*!40000 ALTER TABLE `item_relationships` DISABLE KEYS */;
/*!40000 ALTER TABLE `item_relationships` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `item_requests`
--

DROP TABLE IF EXISTS `item_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `item_requests` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `price` decimal(10,0) DEFAULT NULL,
  `status` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `friend_id` int(11) DEFAULT NULL,
  `request_contract_id` bigint(20) DEFAULT NULL,
  `sent` tinyint(1) NOT NULL DEFAULT '0',
  `step` int(11) DEFAULT '0',
  `accepted_at` datetime DEFAULT NULL,
  `shipped_at` datetime DEFAULT NULL,
  `signed_at` datetime DEFAULT NULL,
  `order_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_item_requests_on_user_id` (`user_id`),
  KEY `index_item_requests_on_request_contract_id` (`request_contract_id`),
  CONSTRAINT `fk_rails_4962f18dcb` FOREIGN KEY (`request_contract_id`) REFERENCES `request_contracts` (`id`),
  CONSTRAINT `fk_rails_596a91ea22` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=300 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `item_requests`
--

LOCK TABLES `item_requests` WRITE;
/*!40000 ALTER TABLE `item_requests` DISABLE KEYS */;
INSERT INTO `item_requests` VALUES (261,7,5,1,'2026-04-12 05:52:02','2026-04-12 06:38:57',1,192,1,1,'2026-04-12 06:38:57',NULL,NULL,100174),(262,7,5,1,'2026-04-12 05:52:35','2026-04-12 06:39:07',1,193,1,1,'2026-04-12 06:39:07',NULL,NULL,100174),(263,7,5,1,'2026-04-12 05:52:49','2026-04-12 16:36:45',1,194,1,2,'2026-04-12 16:36:45',NULL,NULL,100174),(264,1,4,1,'2026-04-12 05:52:49','2026-04-12 05:54:45',10,194,1,1,'2026-04-12 05:54:45',NULL,NULL,100171),(265,7,6,1,'2026-04-12 05:53:03','2026-04-12 14:25:09',1,195,1,2,'2026-04-12 14:25:09',NULL,NULL,NULL),(266,1,5,1,'2026-04-12 05:53:03','2026-04-12 19:43:37',3,195,1,1,'2026-04-12 19:43:37',NULL,NULL,100177),(267,7,7,0,'2026-04-12 05:53:29','2026-04-12 05:53:29',1,196,1,3,NULL,NULL,NULL,NULL),(268,1,6,1,'2026-04-12 05:53:29','2026-04-12 18:13:41',3,196,0,2,'2026-04-12 18:13:41',NULL,NULL,NULL),(269,3,5,1,'2026-04-12 05:53:29','2026-04-12 06:19:21',6,196,1,1,'2026-04-12 06:19:21',NULL,NULL,100172),(270,1,5,1,'2026-04-12 06:07:16','2026-04-12 06:36:04',7,197,1,1,'2026-04-12 06:36:03',NULL,NULL,100173),(271,3,7,1,'2026-04-12 06:11:41','2026-04-12 07:32:41',1,198,1,2,'2026-04-12 07:32:41',NULL,NULL,NULL),(272,1,6,1,'2026-04-12 06:11:41','2026-04-12 14:26:28',10,198,1,1,'2026-04-12 14:26:28',NULL,NULL,100171),(273,6,7,0,'2026-04-12 06:33:53','2026-04-12 06:33:53',3,199,1,2,NULL,NULL,NULL,NULL),(274,3,6,0,'2026-04-12 06:33:53','2026-04-12 06:33:53',4,199,0,1,NULL,NULL,NULL,NULL),(275,6,7,0,'2026-04-12 06:34:19','2026-04-12 06:34:19',3,200,1,2,NULL,NULL,NULL,NULL),(276,3,6,0,'2026-04-12 06:34:19','2026-04-12 06:34:19',4,200,0,1,NULL,NULL,NULL,NULL),(277,7,6,1,'2026-04-12 06:39:53','2026-04-12 14:25:46',1,201,1,2,'2026-04-12 14:25:46',NULL,NULL,NULL),(278,1,5,1,'2026-04-12 06:39:53','2026-04-12 18:12:12',3,201,1,1,'2026-04-12 18:12:12',NULL,NULL,100177),(279,7,6,1,'2026-04-12 07:32:12','2026-04-12 14:25:28',1,202,1,2,'2026-04-12 14:25:28',NULL,NULL,NULL),(280,1,5,1,'2026-04-12 07:32:12','2026-04-12 18:12:48',3,202,1,1,'2026-04-12 18:12:48',NULL,NULL,100177),(281,1,6,1,'2026-04-12 07:34:24','2026-04-12 14:26:38',10,203,1,1,'2026-04-12 14:26:38',NULL,NULL,100171),(282,11,6,1,'2026-04-12 14:32:46','2026-04-12 17:45:32',12,204,1,2,'2026-04-12 17:45:32',NULL,NULL,NULL),(283,12,5,1,'2026-04-12 14:32:46','2026-04-12 18:02:28',7,204,1,1,'2026-04-12 18:02:28',NULL,NULL,100176),(284,11,6,1,'2026-04-12 14:32:56','2026-04-12 17:45:47',12,205,1,2,'2026-04-12 17:45:47',NULL,NULL,NULL),(285,12,5,1,'2026-04-12 14:32:56','2026-04-12 18:02:39',7,205,1,1,'2026-04-12 18:02:39',NULL,NULL,100176),(286,10,6,1,'2026-04-12 14:34:03','2026-04-12 16:42:14',11,206,1,2,'2026-04-12 16:42:14',NULL,NULL,NULL),(287,11,5,1,'2026-04-12 14:34:03','2026-04-12 16:43:13',12,206,1,1,'2026-04-12 16:43:13',NULL,NULL,100175),(288,10,6,1,'2026-04-12 14:34:24','2026-04-12 16:42:03',11,207,1,2,'2026-04-12 16:42:03',NULL,NULL,NULL),(289,11,5,1,'2026-04-12 14:34:24','2026-04-12 16:43:04',12,207,1,1,'2026-04-12 16:43:04',NULL,NULL,100175),(290,11,6,1,'2026-04-12 15:57:11','2026-04-12 18:29:58',10,208,1,1,'2026-04-12 18:29:58',NULL,NULL,100178),(291,11,6,3,'2026-04-12 15:57:21','2026-04-12 15:57:21',10,209,1,1,NULL,NULL,NULL,NULL),(292,11,6,1,'2026-04-12 18:01:14','2026-04-12 18:34:00',12,210,1,2,'2026-04-12 18:34:00',NULL,NULL,100175),(293,12,5,1,'2026-04-12 18:01:14','2026-04-12 18:03:18',7,210,1,1,'2026-04-12 18:03:18',NULL,NULL,100176),(294,1,6,1,'2026-04-12 18:06:49','2026-04-12 18:07:32',7,211,1,2,'2026-04-12 18:07:32',NULL,NULL,NULL),(295,7,5,1,'2026-04-12 18:06:49','2026-04-12 18:34:29',12,211,1,1,'2026-04-12 18:34:29',NULL,NULL,100179),(296,6,5,1,'2026-04-12 18:16:33','2026-04-12 19:43:39',3,212,1,1,'2026-04-12 19:43:39',NULL,NULL,100180),(297,6,5,3,'2026-04-12 18:16:40','2026-04-12 18:16:40',3,213,1,1,NULL,NULL,NULL,NULL),(298,1,6,1,'2026-04-12 18:32:28','2026-04-12 18:33:02',7,214,1,2,'2026-04-12 18:33:02',NULL,NULL,NULL),(299,7,5,1,'2026-04-12 18:32:28','2026-04-12 18:33:36',12,214,1,1,'2026-04-12 18:33:36',NULL,NULL,100179);
/*!40000 ALTER TABLE `item_requests` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `item_units`
--

DROP TABLE IF EXISTS `item_units`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `item_units` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `unit_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `type` int(11) DEFAULT NULL,
  `equivalent` float DEFAULT NULL,
  `item_symbol` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `item_units`
--

LOCK TABLES `item_units` WRITE;
/*!40000 ALTER TABLE `item_units` DISABLE KEYS */;
INSERT INTO `item_units` VALUES (1,'pounds','2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,453.592,'lbs'),(2,'ounces','2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,NULL,'oz'),(3,'boxes','2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,NULL,'box'),(4,'bottles','2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,NULL,'bottle'),(5,'grams','2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,1,'g');
/*!40000 ALTER TABLE `item_units` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `items`
--

DROP TABLE IF EXISTS `items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `items` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `quantity` decimal(10,5) DEFAULT NULL,
  `category_id` bigint(20) DEFAULT NULL,
  `item_name_id` bigint(20) DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `grade_id` bigint(20) DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `date_available` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `item_unit_id` bigint(20) DEFAULT NULL,
  `organic` tinyint(1) DEFAULT '0',
  `producer_id` int(11) DEFAULT NULL,
  `avatars` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_items_on_user_id` (`user_id`),
  KEY `index_items_on_category_id` (`category_id`),
  KEY `index_items_on_item_name_id` (`item_name_id`),
  KEY `index_items_on_grade_id` (`grade_id`),
  KEY `index_items_on_item_unit_id` (`item_unit_id`),
  CONSTRAINT `fk_rails_036cc9f951` FOREIGN KEY (`item_name_id`) REFERENCES `item_names` (`id`),
  CONSTRAINT `fk_rails_6c599fec8d` FOREIGN KEY (`grade_id`) REFERENCES `grades` (`id`),
  CONSTRAINT `fk_rails_89fb86dc8b` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`),
  CONSTRAINT `fk_rails_ae7d35aa51` FOREIGN KEY (`item_unit_id`) REFERENCES `item_units` (`id`),
  CONSTRAINT `fk_rails_d4b6334db2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=82 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `items`
--

LOCK TABLES `items` WRITE;
/*!40000 ALTER TABLE `items` DISABLE KEYS */;
INSERT INTO `items` VALUES (4,7,5.00000,1,2,'Black Krim',5,4.00,'2025-06-22 06:39:54','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,NULL,'[\"1751364851823black_krim2.jpg\", \"1751364866030black_krim.jpg\"]'),(7,7,5.00000,1,3,'Arugula',5,4.00,'2025-06-22 08:33:16','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,7,'[\"17505812007801893957_130425174900_01112_grande.jpeg\", \"1750581208581arugula.jpg\"]'),(8,1,5.00000,1,4,'Basil',6,4.00,'2025-06-22 08:35:56','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,1,'[\"1750581370499basil-with-wet-leaves.jpg\", \"1750581377807basil3.jpg\"]'),(9,12,6.00000,1,6,'Black Cherry',5,4.00,'2025-06-22 08:38:23','2026-04-12 05:49:48','2026-04-12 05:49:48',1,0,12,'[\"1750581529454black_cherry_tomato_2.png\", \"1750581538258black_cherry_tomatoes.jpeg\"]'),(10,12,5.00000,1,7,'Curly Kale',5,4.00,'2025-06-22 08:40:36','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,12,'[\"1750581669721curly_kale_1.jpg\", \"1750581678247curly_kale.jpg\"]'),(11,3,6.00000,1,8,'Early Girl',6,4.00,'2025-06-22 08:53:25','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,3,'[\"1750582443485early_girl_1.png\", \"1750582450068early_girl_2.png\"]'),(12,3,20.00000,1,9,'Cabbage',5,5.00,'2025-06-22 08:55:27','2026-04-12 05:49:48','2026-04-12 05:54:31',1,1,3,'[\"1750582543038cabbage.jpg\", \"1750582550263cabbage2.jpg\"]'),(13,5,10.00000,1,10,'Fennel',6,5.00,'2025-06-22 08:57:47','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,5,'[\"1750582697783fennel.jpeg\", \"1750582705419fennel2.jpg\"]'),(14,5,8.00000,1,11,'Lemon Balm',6,5.00,'2025-06-22 08:59:09','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,NULL,'[\"1750582775973lemon_balm.jpg\", \"1750582803615Lemon_Balm.jpg\"]'),(15,4,10.00000,1,12,'Lettuce',5,5.00,'2025-06-22 09:00:54','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,4,'[\"1750582875945lettuce1.png\", \"1750582882996lettuce3.jpeg\"]'),(16,6,9.00000,1,13,'Mint',6,4.00,'2025-06-22 09:33:57','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,6,'[\"1750584870221mint1.png\", \"1750584879142mint2.png\", \"1750584889094mint3.png\"]'),(17,6,5.00000,1,14,'Hot Peppers',6,6.00,'2025-06-22 09:35:41','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,6,'[\"1750584955954pepper1.png\", \"1750584972672pepper2.jpeg\"]'),(18,10,12.00000,1,15,'Purple Cabbage',5,5.00,'2025-06-22 09:37:38','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,10,'[\"1750585076007purple_cabbage.jpg\", \"1750585082925purple-cabbage.jpg\"]'),(19,10,15.00000,1,17,'Russet Potatoes',6,3.00,'2025-06-22 09:39:10','2026-04-12 05:49:48','2026-04-12 05:49:48',1,1,10,'[\"1750585186332russet_potato_1.jpeg\", \"1750585245264russet_potato_2.jpeg\", \"1750585251749russet_potato_3.jpeg\"]');
/*!40000 ALTER TABLE `items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `jwt_blacklist`
--

DROP TABLE IF EXISTS `jwt_blacklist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `jwt_blacklist` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `jti` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `exp` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_jwt_blacklist_on_jti` (`jti`)
) ENGINE=InnoDB AUTO_INCREMENT=125 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `jwt_blacklist`
--

LOCK TABLES `jwt_blacklist` WRITE;
/*!40000 ALTER TABLE `jwt_blacklist` DISABLE KEYS */;
INSERT INTO `jwt_blacklist` VALUES (1,'f1876015-32b4-498a-bd30-e33b263673c8','2026-06-22 13:10:28'),(2,'8465f151-8a2f-49ed-ba9f-89c7b3b58dc2','2026-06-22 13:54:41'),(3,'3c4865ed-783b-4b2d-a102-d98835abae0a','2026-06-22 13:55:12'),(4,'11806ed0-38b4-47f6-891b-c043fe42c151','2026-06-22 20:06:57'),(5,'02fadfdf-88c7-4271-9282-f926942efd79','2026-06-22 20:10:54'),(6,'1d5c8e3a-e21a-43df-8ddd-cee2c12f094e','2026-06-22 20:27:54'),(7,'2ff024a0-98a9-4956-ad41-4583f089a885','2026-06-22 20:30:09'),(8,'441e629d-31f6-4728-bdb2-af8786d1ef3b','2026-06-22 20:31:31'),(9,'f7bddf3b-abd7-43a2-95ce-fe4d4b3640c1','2026-06-22 20:33:03'),(10,'e133e002-6f9a-4121-babe-5d4068a322c2','2026-06-22 20:40:05'),(11,'8e8af280-3e32-4c9f-a980-9372ee5ff859','2026-06-22 20:40:28'),(12,'342dfba7-206c-4734-8946-95b4fb646938','2026-06-22 23:12:22'),(13,'e60a5df2-caca-4e00-8551-d8a5be419f5a','2026-06-22 23:14:32'),(14,'94f4b020-b081-454d-99df-ab39f8676cb7','2026-06-22 23:14:56'),(15,'9e577c73-733f-40e5-9a84-8c37b67d2831','2026-06-22 23:17:16'),(16,'3d1f1fc3-32de-4953-aef7-dfe3a64296c7','2026-06-22 23:17:38'),(17,'583432d7-2761-408c-9671-b074a5197ed3','2026-06-22 23:53:50'),(18,'22ea7833-45f4-4eca-acbe-8e7237955742','2026-06-22 23:54:11'),(19,'3a335b47-95a6-444a-8b29-b5ef22b43d07','2026-06-23 00:38:03'),(20,'bea0bd8b-6754-4b38-857a-52ba6dc0abc1','2026-06-23 08:44:49'),(21,'aec1925c-0a28-4277-abe8-73c7e7fa13cd','2026-06-23 08:45:02'),(22,'bd0cfebd-e33d-4933-9c41-6b0f73b6100c','2026-06-23 09:22:23'),(23,'42bec547-e6ef-4e05-81ef-3ba6831b8172','2026-06-23 09:23:30'),(24,'85402357-4f52-43ae-a5a9-3d471bbcef6a','2026-06-23 09:25:18'),(25,'a4fe3929-958d-4968-92a8-5506afe85a41','2026-06-23 08:44:18'),(26,'51fc6b60-ebf2-40dc-a1ef-f738aee43bba','2026-06-23 09:15:32'),(27,'6082de87-f2ea-42de-bd68-72000becfeba','2026-06-23 10:54:16'),(28,'5cc70975-8ae4-456d-8d13-eb47943d5c44','2026-06-23 11:04:52'),(29,'b345a219-1af9-486b-bce4-48c781b4867f','2026-06-23 10:54:34'),(30,'40e72f36-2e34-439f-968d-bd4512f8d254','2026-06-23 11:07:56'),(31,'095c7a51-29f1-42bd-8707-826bc50e2e5a','2026-06-23 11:36:36'),(32,'0ccec8aa-5193-4084-ad23-17711dc624f1','2026-06-23 11:18:02'),(33,'82a401cf-6da0-4a26-9080-07770cfe2812','2026-06-23 14:53:07'),(34,'51ef2cc3-097c-4e9b-ab2d-59ddb25c1b16','2026-06-23 15:16:39'),(35,'9301d3d9-3f70-498b-ad27-b3e51b9cb0a4','2026-06-23 15:17:06'),(36,'0db614c4-2031-4159-928a-0eabdad08ae2','2026-06-23 15:22:35'),(37,'de6a4d69-d9f3-4b25-9508-83462a963bf4','2026-06-23 18:55:21'),(38,'b16d880e-2912-4b9d-b7fd-5a321062d43f','2026-06-23 23:21:07'),(39,'02f9a233-cb44-4ce3-9ad0-d1846513bf1f','2026-06-23 23:21:33'),(40,'52750c23-571c-4daa-a207-977be42741f3','2026-06-23 18:55:50'),(41,'27116c29-1d2f-4bb0-a694-f05c421636c5','2026-06-24 15:55:28'),(42,'da29fb1e-3e7e-4436-bc53-9e89d9c61464','2026-06-25 08:39:45'),(43,'4dea9c83-db27-4fc2-81fc-ffc6b6b2f0a4','2026-06-25 08:40:23'),(44,'0b9c0325-76ff-4d8c-b883-d0fcb448afdb','2026-06-25 11:07:08'),(45,'426ee2b7-eac3-457b-86d0-5b8ffbb1f990','2026-06-24 13:33:04'),(46,'9ddeeb23-97df-434d-b123-28c276e3456d','2026-06-25 13:02:14'),(47,'423dd19d-1cf8-4f2c-9c57-4367db346b57','2026-06-25 14:37:16'),(48,'f5d2d101-c55d-4ba2-9ea1-d0c98303d99e','2026-06-25 18:21:04'),(49,'ab53105f-1e98-4103-a4f2-be2f0ae2b0ad','2026-06-25 20:26:15'),(50,'c80d92e1-25f4-4144-a15c-d8c58400bfeb','2026-06-26 07:57:43'),(51,'e1173f87-5f90-4270-bc54-0cfce0b70be0','2026-06-26 11:45:47'),(52,'356f03c4-b002-488c-b911-ad29c84a4f92','2026-06-26 11:58:42'),(53,'b153321e-98c7-435e-88d0-0d02431162e7','2026-06-26 12:00:34'),(54,'33192176-c090-4252-a22e-10d5e9e991d1','2026-06-26 13:07:41'),(55,'9dfb2e8c-53dc-4b86-af39-6cc2e2f18881','2026-06-26 13:07:57'),(56,'9008eef6-5919-425e-9ef6-7d6b6bce8939','2026-06-26 14:34:15'),(57,'e951a2e8-0505-4261-829b-0d66450621f0','2026-06-26 14:36:07'),(58,'59a4eec3-e30a-4611-9b33-3581174c547a','2026-06-26 14:36:31'),(59,'23cc5cfe-fdd0-468a-b40d-e908ed5e6331','2026-06-26 14:36:43'),(60,'3c51ee99-6590-489c-8256-798c46d49dba','2026-06-27 09:41:18'),(61,'15964ded-8fae-44f4-b18a-c74c80623d95','2026-06-27 14:45:08'),(62,'edfcea4e-ab47-42a5-9807-aca79c7f6f33','2026-06-27 16:21:48'),(63,'c3261221-dcf7-4ea2-9301-0c3f6727c846','2026-06-27 20:35:54'),(64,'3e1e9f33-ac53-4768-ab5a-120f6389a056','2026-06-27 22:46:02'),(65,'a594bc66-ed14-4990-8f71-34a0d8c5eb0f','2026-06-27 22:46:15'),(66,'dac80dfe-e5a1-4c51-b941-a106d1c75e2c','2026-06-28 03:33:23'),(67,'55cb7981-a632-4b01-b7b7-ce33f2db6d96','2026-06-28 04:13:16'),(68,'0ea872bc-1580-43a0-84b9-ce0dd179affc','2026-06-28 05:27:32'),(69,'b166b3d2-0b0b-426d-afa4-87571e16f533','2026-06-28 09:11:03'),(70,'d0dfb791-ff95-461c-91df-205ac864d5ba','2026-06-28 10:03:35'),(71,'aea6c175-fced-42f4-ae50-0613a6be7472','2026-06-28 10:03:55'),(72,'5cc691eb-8dc6-41f8-8540-0c545606d0dc','2026-06-28 10:04:50'),(73,'03b7ce74-9541-4016-bdc7-ba55b7869917','2026-06-28 10:48:39'),(74,'d4105746-b6df-4be0-a1fd-1e423231d4bb','2026-06-30 06:56:38'),(75,'de0c10a3-7adf-4d37-bd05-5b59f91228e7','2026-06-30 07:39:56'),(76,'9ebb7d6d-7bde-4ca7-9df6-dd61be1fcf1a','2026-06-30 08:32:51'),(77,'c54ff26a-7f54-4376-8318-9d4be034cb6f','2026-06-30 08:40:48'),(78,'92b0b776-5efb-4bdd-92aa-1b59c1342da1','2026-06-30 08:41:14'),(79,'3df6fea8-b46c-4e7c-b0a3-2409fdb28102','2026-07-01 07:39:32'),(80,'bbca24ef-fcc5-4c6f-ac9d-1959b7702636','2026-07-01 08:48:29'),(81,'aa4e8440-f442-487d-9ff7-3065572b73bb','2026-07-01 09:33:18'),(82,'6a174786-9b4a-44c6-b1e5-6a69aad0ff12','2026-07-01 11:17:49'),(83,'053d9ee7-3561-45c9-8c9f-870ce4a262e2','2026-06-25 15:19:45'),(84,'148552d6-328b-4798-b3fe-3f45282f2ce0','2026-07-01 12:53:28'),(85,'e7b2c694-8c78-4fe2-8a57-662e53827cb3','2026-07-01 12:49:58'),(86,'b1067ba2-4792-4871-9ed8-89e6728ead30','2026-07-01 13:23:31'),(87,'b73bef9a-d799-4964-9147-61987bab39b6','2026-07-01 12:54:08'),(88,'5c813491-2ae6-4716-bf5a-9c116cd929b7','2026-07-01 17:31:06'),(89,'8196ff03-2aa7-4fee-81a8-f962108098be','2026-07-02 17:02:28'),(90,'982a69fd-22a2-4281-992a-e404c8ffd923','2026-07-03 15:49:40'),(91,'ba6f4501-b819-4a45-a188-53f3e2c6ce1b','2026-07-03 21:17:52'),(92,'db281fb1-58d9-4d3e-b3c7-2522cde078db','2026-07-04 08:26:36'),(93,'fdb8a149-f815-4d36-be76-c5f2aae586e2','2026-07-04 09:47:43'),(94,'fb257250-9f2b-4140-9197-427f14124ff8','2026-07-04 10:47:40'),(95,'9ca7bf81-a449-4d39-85d9-ce6d9f06ee85','2026-07-04 20:05:05'),(96,'4edacbf7-a4f0-4d0d-8090-3d0b5aecf829','2026-07-01 14:23:28'),(97,'01ca0fdc-b012-4e37-bbbb-3a451a64e8a9','2026-07-06 17:36:15'),(98,'60c61c60-af76-4393-8496-5e0dc0360edd','2026-07-06 18:56:27'),(99,'19281ccc-65a1-44af-908a-cd74bbf4d741','2026-07-07 19:23:14'),(100,'3502b2d7-303f-45b8-a579-7727ae555e96','2026-07-07 20:46:24'),(101,'7ebaaf92-d312-4668-b382-13aa2c2f242d','2026-07-07 22:06:17'),(102,'cbebfc9c-41e9-4ad1-ad0f-6f570bfdb734','2026-07-07 22:06:34'),(103,'7491adfc-fd10-431b-aa3d-34aa32ade106','2026-07-07 22:07:57'),(104,'cdcc4d42-ca43-4a59-912e-c6f3a07fc61e','2026-07-07 22:08:49'),(105,'8d01a982-11a2-4b81-a8ed-58532159b1db','2026-07-07 22:09:14'),(106,'7949bcc0-37e3-4e51-a749-6d3bf6015f0f','2026-07-07 22:09:39'),(107,'39b20019-75f8-4eaf-8ab9-a03bc162634b','2026-07-07 22:10:02'),(108,'5f00c3bb-d130-4abf-acd3-570654432b7e','2026-06-22 20:59:41'),(109,'90b4ce09-06a2-408e-ac7f-4561aeeeaa9c','2027-03-20 21:09:14'),(110,'3b0bb8e3-b77d-49b3-bd8b-a414256c3e3f','2027-04-07 04:26:07'),(111,'590abd87-9400-46da-aafb-467e060b9901','2027-04-07 05:38:08'),(112,'e049507b-bd07-4b64-acc0-d9052befba07','2027-04-07 05:42:34'),(113,'5559ff32-7395-4825-823a-f640593394c1','2027-04-07 05:47:37'),(114,'84e9c20f-1ccc-4758-843a-ec806a2ab03c','2027-04-08 06:05:01'),(115,'2b190d6b-afbc-4afd-b4a3-6fc58fd33f10','2027-04-08 04:32:50'),(116,'66d1aeac-fe12-47db-ba97-61a0e21830fc','2027-04-08 06:29:43'),(117,'1253f18a-489f-4c76-8cfd-8b0f99179f56','2027-04-08 06:31:08'),(118,'9024946f-4597-4bc0-9de9-98591f0aabde','2027-04-08 06:31:31'),(119,'71ef53f0-8a4a-47c4-8ff4-c619e597082c','2027-04-08 20:44:38'),(120,'58699975-df69-451a-b82c-80f3f511f6e2','2027-04-09 03:40:22'),(121,'54eff5aa-5ee0-4799-ae4b-4b6cae464141','2027-04-09 04:26:05'),(122,'ba21a72b-7ba6-4402-8bf0-410740b7f65c','2027-04-09 19:19:01'),(123,'4753d9bd-a868-47e8-8edb-50f56638a8d2','2027-04-09 23:32:39'),(124,'75c16605-5487-4249-81f4-8fd9135fe436','2027-04-10 01:37:29');
/*!40000 ALTER TABLE `jwt_blacklist` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `orders` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `friend_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `order_label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `order_total` decimal(10,0) DEFAULT NULL,
  `order_status` int(11) DEFAULT NULL,
  `estimated_date` datetime DEFAULT NULL,
  `shipped_on` datetime DEFAULT NULL,
  `signed_on` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `estimated_time` time DEFAULT NULL,
  `location` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pick up',
  `note` text COLLATE utf8mb4_unicode_ci,
  `settlement_type` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `settlement_status` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `settlement_proposed_by` int(11) DEFAULT NULL,
  `settlement_counter_type` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `settlement_counter_by` int(11) DEFAULT NULL,
  `cash_amount` decimal(10,2) DEFAULT NULL,
  `cash_paid_by` int(11) DEFAULT NULL,
  `cash_confirmed_by` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=100181 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `orders`
--

LOCK TABLES `orders` WRITE;
/*!40000 ALTER TABLE `orders` DISABLE KEYS */;
INSERT INTO `orders` VALUES (100171,'1','10','Order 100171',11,0,NULL,NULL,NULL,'2026-04-12 05:54:45','2026-04-12 14:26:38',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100172,'3','6','Order 100172',1,0,NULL,NULL,NULL,'2026-04-12 06:19:21','2026-04-12 06:19:21',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100173,'1','7','Order 100173',1,0,NULL,NULL,NULL,'2026-04-12 06:36:04','2026-04-12 06:36:04',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100174,'7','1','Order 100174',7,0,NULL,NULL,NULL,'2026-04-12 06:38:57','2026-04-12 16:36:45',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100175,'11','12','Order 100175',5,0,NULL,NULL,NULL,'2026-04-12 16:43:04','2026-04-12 18:34:00',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100176,'12','7','Order 100176',4,0,NULL,NULL,NULL,'2026-04-12 18:02:28','2026-04-12 18:03:18',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100177,'1','3','Order 100177',3,0,NULL,NULL,NULL,'2026-04-12 18:12:12','2026-04-12 19:43:37',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100178,'11','10','Order 100178',2,0,NULL,NULL,NULL,'2026-04-12 18:29:58','2026-04-12 18:29:58',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100179,'7','12','Order 100179',4,0,NULL,NULL,NULL,'2026-04-12 18:33:36','2026-04-12 18:34:29',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),(100180,'6','3','Order 100180',2,0,NULL,NULL,NULL,'2026-04-12 19:43:39','2026-04-12 19:43:39',NULL,'pick up',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
/*!40000 ALTER TABLE `orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `relationships`
--

DROP TABLE IF EXISTS `relationships`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `relationships` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `friend_id` int(11) DEFAULT NULL,
  `status` int(11) DEFAULT '0',
  `action_user_id` int(11) DEFAULT NULL,
  `user_id` bigint(20) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `user_label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `friend_label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `actions_state` int(11) DEFAULT '0',
  `friend_actions_state` int(11) DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_relationships_on_user_id` (`user_id`),
  CONSTRAINT `fk_rails_a3d77c3b00` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=197 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `relationships`
--

LOCK TABLES `relationships` WRITE;
/*!40000 ALTER TABLE `relationships` DISABLE KEYS */;
INSERT INTO `relationships` VALUES (183,2,1,1,1,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(184,3,1,1,1,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(185,4,1,3,3,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(186,5,1,3,3,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(187,6,1,3,3,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(188,7,1,1,1,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(189,8,1,7,7,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(190,9,1,8,8,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(191,10,1,1,1,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(192,11,1,10,10,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(193,12,1,7,7,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(194,12,1,12,11,'2026-04-12 05:49:48','2026-04-12 05:49:48',NULL,NULL,0,0),(195,13,1,12,12,'2026-04-12 05:49:48','2026-04-12 05:49:48','',NULL,0,0),(196,8,0,NULL,6,'2026-04-12 19:14:19','2026-04-12 19:20:47','',NULL,1,0);
/*!40000 ALTER TABLE `relationships` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `request_contracts`
--

DROP TABLE IF EXISTS `request_contracts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `request_contracts` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `item_id` bigint(20) DEFAULT NULL,
  `quantity` decimal(10,5) DEFAULT NULL,
  `status` int(11) DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `inventory_id` int(11) DEFAULT NULL,
  `steps` int(11) DEFAULT '0',
  `current_step` int(11) DEFAULT '0',
  `deleted_at` datetime DEFAULT NULL,
  `deleted_by` datetime DEFAULT NULL,
  `archived` tinyint(1) DEFAULT '0',
  `unit` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_request_contracts_on_user_id` (`user_id`),
  KEY `index_request_contracts_on_item_id` (`item_id`),
  CONSTRAINT `fk_rails_47c32767bf` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_56551eb80e` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=215 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `request_contracts`
--

LOCK TABLES `request_contracts` WRITE;
/*!40000 ALTER TABLE `request_contracts` DISABLE KEYS */;
INSERT INTO `request_contracts` VALUES (192,7,15,1.00000,1,'2026-04-12 05:52:02','2026-04-12 06:38:57',566,1,0,NULL,NULL,0,NULL),(193,7,14,1.00000,1,'2026-04-12 05:52:35','2026-04-12 06:39:07',567,1,0,NULL,NULL,0,NULL),(194,7,17,5.00000,1,'2026-04-12 05:52:49','2026-04-12 16:36:45',570,2,0,NULL,NULL,0,NULL),(195,7,7,1.00000,1,'2026-04-12 05:53:03','2026-04-12 19:43:37',582,2,0,NULL,NULL,0,NULL),(196,7,12,1.00000,0,'2026-04-12 05:53:29','2026-04-12 06:19:21',564,3,0,NULL,NULL,0,NULL),(197,1,9,1.00000,1,'2026-04-12 06:07:16','2026-04-12 06:36:04',565,1,0,NULL,NULL,0,NULL),(198,3,16,1.00000,1,'2026-04-12 06:11:41','2026-04-12 14:26:28',568,2,0,NULL,NULL,0,NULL),(199,6,18,2.00000,0,'2026-04-12 06:33:53','2026-04-12 06:33:53',551,2,0,NULL,NULL,0,NULL),(200,6,9,2.00000,0,'2026-04-12 06:34:19','2026-04-12 06:34:19',537,2,0,NULL,NULL,0,NULL),(201,7,8,1.00000,1,'2026-04-12 06:39:53','2026-04-12 18:12:12',576,2,0,NULL,NULL,0,NULL),(202,7,4,1.00000,1,'2026-04-12 07:32:12','2026-04-12 18:12:48',577,2,0,NULL,NULL,0,NULL),(203,1,12,5.00000,1,'2026-04-12 07:34:24','2026-04-12 14:26:38',569,1,0,NULL,NULL,0,NULL),(204,11,14,1.00000,1,'2026-04-12 14:32:46','2026-04-12 18:02:28',573,2,0,NULL,NULL,0,NULL),(205,11,11,1.00000,1,'2026-04-12 14:32:56','2026-04-12 18:02:39',574,2,0,NULL,NULL,0,NULL),(206,10,18,1.00000,1,'2026-04-12 14:34:03','2026-04-12 16:43:13',572,2,0,NULL,NULL,0,NULL),(207,10,19,2.00000,1,'2026-04-12 14:34:24','2026-04-12 16:43:04',571,2,0,NULL,NULL,0,NULL),(208,11,12,2.00000,1,'2026-04-12 15:57:11','2026-04-12 18:29:58',578,1,0,NULL,NULL,0,NULL),(209,11,12,2.00000,3,'2026-04-12 15:57:21','2026-04-12 15:59:45',554,1,0,NULL,NULL,0,NULL),(210,11,15,2.00000,1,'2026-04-12 18:01:14','2026-04-12 18:34:00',580,2,0,NULL,NULL,0,NULL),(211,1,18,2.00000,1,'2026-04-12 18:06:49','2026-04-12 18:34:29',581,2,0,NULL,NULL,0,NULL),(212,6,7,2.00000,1,'2026-04-12 18:16:33','2026-04-12 19:43:39',583,1,0,NULL,NULL,0,NULL),(213,6,7,2.00000,3,'2026-04-12 18:16:40','2026-04-12 18:16:48',533,1,0,NULL,NULL,0,NULL),(214,1,16,2.00000,1,'2026-04-12 18:32:28','2026-04-12 18:33:36',579,2,0,NULL,NULL,0,NULL);
/*!40000 ALTER TABLE `request_contracts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `request_list_relationship_statuses`
--

DROP TABLE IF EXISTS `request_list_relationship_statuses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `request_list_relationship_statuses` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `relationship_id` bigint(20) DEFAULT NULL,
  `status` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `item_request_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_request_list_relationship_statuses_on_relationship_id` (`relationship_id`),
  KEY `index_request_list_relationship_statuses_on_item_request_id` (`item_request_id`),
  CONSTRAINT `fk_rails_3be211eeea` FOREIGN KEY (`item_request_id`) REFERENCES `item_requests` (`id`),
  CONSTRAINT `fk_rails_937d024733` FOREIGN KEY (`relationship_id`) REFERENCES `relationships` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `request_list_relationship_statuses`
--

LOCK TABLES `request_list_relationship_statuses` WRITE;
/*!40000 ALTER TABLE `request_list_relationship_statuses` DISABLE KEYS */;
/*!40000 ALTER TABLE `request_list_relationship_statuses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `reviews`
--

DROP TABLE IF EXISTS `reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reviews` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `item_name_id` bigint(20) DEFAULT NULL,
  `item_id` bigint(20) DEFAULT NULL,
  `producer_id` int(11) DEFAULT NULL,
  `value` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_reviews_on_user_id` (`user_id`),
  KEY `index_reviews_on_item_name_id` (`item_name_id`),
  KEY `index_reviews_on_item_id` (`item_id`),
  CONSTRAINT `fk_rails_1b37fb5a2a` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`),
  CONSTRAINT `fk_rails_74a66bd6c5` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_98df850281` FOREIGN KEY (`item_name_id`) REFERENCES `item_names` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `reviews`
--

LOCK TABLES `reviews` WRITE;
/*!40000 ALTER TABLE `reviews` DISABLE KEYS */;
/*!40000 ALTER TABLE `reviews` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `schema_migrations`
--

DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schema_migrations` (
  `version` varchar(255) CHARACTER SET utf8 COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `schema_migrations`
--

LOCK TABLES `schema_migrations` WRITE;
/*!40000 ALTER TABLE `schema_migrations` DISABLE KEYS */;
INSERT INTO `schema_migrations` VALUES ('20181005144412'),('20181005161210'),('20181009105102'),('20181009105826'),('20181009141123'),('20181010011344'),('20181010011709'),('20181010044205'),('20181015111634'),('20181015141508'),('20181016141706'),('20181016141800'),('20181019080406'),('20181019084146'),('20181019085108'),('20181022081506'),('20181022104338'),('20181022105107'),('20181023113502'),('20181024082439'),('20181025083930'),('20181101125759'),('20181101131408'),('20181102052157'),('20181102054039'),('20181102063418'),('20181102064500'),('20181102064853'),('20181102064916'),('20181102065037'),('20181102065448'),('20181102071750'),('20181102075815'),('20181102095604'),('20181102095826'),('20181102100117'),('20181102100234'),('20181102100454'),('20181103110803'),('20181104093029'),('20181105104929'),('20181105105333'),('20181105105920'),('20181105110239'),('20181105110406'),('20181105110627'),('20181105110700'),('20181105110724'),('20181105110759'),('20181105124606'),('20181106025354'),('201811070122202'),('20181114011154'),('20181128200407'),('20181128201905'),('20181128201926'),('20181128202024'),('20181128202057'),('20181128202212'),('20181201023333'),('20190108214619'),('20190111081833'),('20190113133724'),('20190113171909'),('20190115062006'),('20190116141205'),('20190128202223'),('20190201024857'),('20190201073738'),('20190201193545'),('20190629103608'),('20190629105212'),('20190702083532'),('20190702084144'),('20190708202239'),('20190715085203'),('20190719105604'),('20190719175607'),('20190719183221'),('20190801190819'),('20190802122405'),('20200212124528'),('20200212142201'),('20200213084015'),('20200323220353'),('20200415144533'),('20200416160821'),('20200416171441'),('20200420161824'),('20200422152529'),('20200425230910'),('20200426143411'),('20200426173808'),('20200429124328'),('20250624085633'),('20250624100523'),('20260410211409'),('20260410233422');
/*!40000 ALTER TABLE `schema_migrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `trustline_transactions`
--

DROP TABLE IF EXISTS `trustline_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `trustline_transactions` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `trustline_id` bigint(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `originating_request_id` bigint(20) DEFAULT NULL,
  `order_id` bigint(20) DEFAULT NULL,
  `path_info` json DEFAULT NULL,
  `transaction_type` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `initiated_by_id` bigint(20) NOT NULL,
  `balance_after` decimal(10,2) DEFAULT NULL,
  `is_reversed` tinyint(1) DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_trustline_transactions_on_trustline_id` (`trustline_id`),
  KEY `index_trustline_transactions_on_originating_request_id` (`originating_request_id`),
  KEY `index_trustline_transactions_on_order_id` (`order_id`),
  KEY `index_trustline_transactions_on_initiated_by_id` (`initiated_by_id`),
  KEY `index_trustline_transactions_on_transaction_type` (`transaction_type`),
  KEY `index_trustline_transactions_on_created_at` (`created_at`),
  KEY `index_trustline_transactions_on_is_reversed` (`is_reversed`),
  CONSTRAINT `fk_rails_3bad747ecc` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`),
  CONSTRAINT `fk_rails_5eaae8463f` FOREIGN KEY (`originating_request_id`) REFERENCES `item_requests` (`id`),
  CONSTRAINT `fk_rails_c316734e8c` FOREIGN KEY (`trustline_id`) REFERENCES `trustlines` (`id`),
  CONSTRAINT `fk_rails_dc8d3c88fc` FOREIGN KEY (`initiated_by_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `trustline_transactions`
--

LOCK TABLES `trustline_transactions` WRITE;
/*!40000 ALTER TABLE `trustline_transactions` DISABLE KEYS */;
/*!40000 ALTER TABLE `trustline_transactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `trustlines`
--

DROP TABLE IF EXISTS `trustlines`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `trustlines` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_a_id` bigint(20) NOT NULL,
  `user_b_id` bigint(20) NOT NULL,
  `credit_limit_a_to_b` decimal(10,2) NOT NULL DEFAULT '0.00',
  `credit_limit_b_to_a` decimal(10,2) NOT NULL DEFAULT '0.00',
  `current_balance` decimal(10,2) NOT NULL DEFAULT '0.00',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `established_date` datetime NOT NULL,
  `last_activity` datetime DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_trustlines_on_user_pair` (`user_a_id`,`user_b_id`),
  KEY `index_trustlines_on_user_a_id` (`user_a_id`),
  KEY `index_trustlines_on_user_b_id` (`user_b_id`),
  KEY `index_trustlines_on_is_active` (`is_active`),
  KEY `index_trustlines_on_established_date` (`established_date`),
  CONSTRAINT `fk_rails_8c2346fdd9` FOREIGN KEY (`user_b_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_9866b2b2d9` FOREIGN KEY (`user_a_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `trustlines`
--

LOCK TABLES `trustlines` WRITE;
/*!40000 ALTER TABLE `trustlines` DISABLE KEYS */;
/*!40000 ALTER TABLE `trustlines` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `unit_options`
--

DROP TABLE IF EXISTS `unit_options`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `unit_options` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `inventory_id` int(11) NOT NULL,
  `item_unit_id` int(11) NOT NULL,
  `price` float DEFAULT NULL,
  `quantity` float DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `unit_options`
--

LOCK TABLES `unit_options` WRITE;
/*!40000 ALTER TABLE `unit_options` DISABLE KEYS */;
/*!40000 ALTER TABLE `unit_options` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_category_prices`
--

DROP TABLE IF EXISTS `user_category_prices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_category_prices` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `category_id` bigint(20) DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `unit` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_category_prices_on_user_id` (`user_id`),
  KEY `index_user_category_prices_on_category_id` (`category_id`),
  CONSTRAINT `fk_rails_3443e5b024` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`),
  CONSTRAINT `fk_rails_d762a78e18` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_category_prices`
--

LOCK TABLES `user_category_prices` WRITE;
/*!40000 ALTER TABLE `user_category_prices` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_category_prices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_groups`
--

DROP TABLE IF EXISTS `user_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_groups` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `group_label` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_groups_on_user_id` (`user_id`),
  CONSTRAINT `fk_rails_c298be7f8b` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=407 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_groups`
--

LOCK TABLES `user_groups` WRITE;
/*!40000 ALTER TABLE `user_groups` DISABLE KEYS */;
INSERT INTO `user_groups` VALUES (28,14,7,'2026-04-10 17:05:56','2026-04-10 17:05:56'),(380,1,5,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(381,2,1,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(382,3,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(383,4,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(384,5,1,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(385,6,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(386,7,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(387,8,3,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(388,9,0,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(389,10,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(390,11,3,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(391,12,2,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(392,12,3,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(393,13,1,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(394,1,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(395,2,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(396,3,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(397,4,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(398,5,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(399,6,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(400,7,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(401,8,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(402,10,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(403,11,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(404,12,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(405,9,6,'2026-04-12 05:49:48','2026-04-12 05:49:48'),(406,13,6,'2026-04-12 05:49:48','2026-04-12 05:49:48');
/*!40000 ALTER TABLE `user_groups` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_relationship_prices`
--

DROP TABLE IF EXISTS `user_relationship_prices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_relationship_prices` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `friend_id` int(11) DEFAULT NULL,
  `category_id` bigint(20) DEFAULT NULL,
  `relationship_id` bigint(20) DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `receiving_price` decimal(10,2) DEFAULT NULL,
  `receiving_price_type` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_relationship_prices_on_user_id` (`user_id`),
  KEY `index_user_relationship_prices_on_category_id` (`category_id`),
  KEY `index_user_relationship_prices_on_relationship_id` (`relationship_id`),
  CONSTRAINT `fk_rails_1a4a7db840` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_56dfc822ed` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`),
  CONSTRAINT `fk_rails_7b6064acac` FOREIGN KEY (`relationship_id`) REFERENCES `relationships` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_relationship_prices`
--

LOCK TABLES `user_relationship_prices` WRITE;
/*!40000 ALTER TABLE `user_relationship_prices` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_relationship_prices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_relationship_request_prices`
--

DROP TABLE IF EXISTS `user_relationship_request_prices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_relationship_request_prices` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `friend_id` int(11) DEFAULT NULL,
  `relationship_id` bigint(20) DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `item_request_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_relationship_request_prices_on_user_id` (`user_id`),
  KEY `index_user_relationship_request_prices_on_relationship_id` (`relationship_id`),
  KEY `index_user_relationship_request_prices_on_item_request_id` (`item_request_id`),
  CONSTRAINT `fk_rails_7a180ac534` FOREIGN KEY (`relationship_id`) REFERENCES `relationships` (`id`),
  CONSTRAINT `fk_rails_7aa04ab378` FOREIGN KEY (`item_request_id`) REFERENCES `item_requests` (`id`),
  CONSTRAINT `fk_rails_b934845619` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_relationship_request_prices`
--

LOCK TABLES `user_relationship_request_prices` WRITE;
/*!40000 ALTER TABLE `user_relationship_request_prices` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_relationship_request_prices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `encrypted_password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `reset_password_token` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reset_password_sent_at` datetime DEFAULT NULL,
  `remember_created_at` datetime DEFAULT NULL,
  `sign_in_count` int(11) NOT NULL DEFAULT '0',
  `current_sign_in_at` datetime DEFAULT NULL,
  `last_sign_in_at` datetime DEFAULT NULL,
  `current_sign_in_ip` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `last_sign_in_ip` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `nickname` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `image` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tokens` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `invitation_limit` int(11) DEFAULT NULL,
  `invited_by_id` bigint(20) DEFAULT NULL,
  `invitations_count` int(11) DEFAULT '0',
  `user_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `invitation_code` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `depth` int(11) DEFAULT '3',
  `invite_limit` int(11) DEFAULT '3',
  `invited_code` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `parent_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_users_on_user_name` (`user_name`),
  UNIQUE KEY `index_users_on_email` (`email`),
  UNIQUE KEY `index_users_on_reset_password_token` (`reset_password_token`),
  KEY `index_users_on_invited_by_type_and_invited_by_id` (`invited_by_id`),
  KEY `index_users_on_invitations_count` (`invitations_count`),
  KEY `index_users_on_invited_by_id` (`invited_by_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'$2a$11$Dt.Vw2TMVGfRQuEyD4xEsexJe1aAjYCJivHh18AZYzljofapQiW9S',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:48',NULL,NULL,4,'bob',NULL,0,1000000,NULL,NULL),(2,'$2a$11$Dy0fJl6zSlR9Ta31lWzEX.Ti1U4xPP1U249CO8zazZ33WVe5dwIwy',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:44',NULL,NULL,0,'dianna',NULL,1,3,'JZA7SNVP',1),(3,'$2a$11$Yga6dIGVTWDvyASc0x9zg.RlwziEGW2TAkWQE7MhnzHaexgAMMtPG',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:46',NULL,NULL,3,'peter',NULL,1,3,'G71N3T0S',1),(4,'$2a$11$0/gjhS8E0zn4.SlS3VBaP.rEbKpCCzRFE.pzd633MpP6d64UULXui',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:45','2025-06-18 01:07:45',NULL,NULL,0,'paul',NULL,2,3,'MQJK3BG5',3),(5,'$2a$11$YSHc9lmpuWhHpz0i.ZTxTe5YTXn.fw67NJmXDTMLQjfO1ynsHqrhi',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:45','2025-06-18 01:07:45',NULL,NULL,0,'sara',NULL,2,3,'NJ2QPLW0',3),(6,'$2a$11$wvMEx6pdPO15iFV0qGbOaOHHYhBgP9uh8NfUvdqPKW.e5Vgvzi4ka',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:46','2025-06-18 01:07:46',NULL,NULL,0,'mary',NULL,2,3,'UZSGTY3V',3),(7,'$2a$11$WHTheF8F8aK4qfxGN5HyJuTvm9Q5S0toIgt3VsIB6pJFl7PDCBsym',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:46','2025-06-30 08:41:03',NULL,NULL,2,'bruce',NULL,1,7,'H4KC2AJS',1),(8,'$2a$11$HKtxADkSmPBaTC4zrK2dJeTAc1gpgKPNBcb/PQ.1ik6R0wpIdmmpS',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:47','2025-06-18 01:07:47',NULL,NULL,1,'arthur',NULL,2,3,'6DN58LU1',7),(9,'$2a$11$.ii/6sDsJvghPXP8zYVJ8ONu2kD6zCAmWlr5oVPC9nHeIXgo6wJT2',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:47','2025-06-18 01:07:47',NULL,NULL,0,'mark',NULL,3,3,'NMEZVDL0',8),(10,'$2a$11$fSYusSBihmL3Z9ksjTE.Ce4OaaBFYE1YmgHG0AOn616baHRldK3y2',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:48','2025-06-18 01:07:48',NULL,NULL,1,'clark',NULL,1,3,'I3U8KDJW',1),(11,'$2a$11$UQigDwidGR5pg2NvQHCDSO6n4xWodxlW.oCBSu1LSepMOG.PjB.xy',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:48','2025-06-18 01:07:48',NULL,NULL,0,'oliver',NULL,2,3,'KGR7LN08',10),(12,'$2a$11$4CymLEbq.hkRBypwTjQifOQ1I7UOoIBLpCEtcjQSAGmlSAPQN5aRG',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,'avatar.jpg',NULL,NULL,'2025-06-18 01:07:48','2026-04-11 22:24:03',NULL,NULL,1,'barry',NULL,2,3,'EDB2P85X',7),(13,'$2a$11$yYCvydy.w6s0w3f2MGSxF.svWWbPGQZwA1Ys5xvVCETy.mzynf9/q',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,NULL,0,'john',NULL,3,3,'2J46IVHR',12),(14,'$2a$11$AlQdC1pLscbWZWkAxtoHRu/0YCKYs0sOsq5bdO5IygmLqJBTdXaAu',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-04-10 17:05:56','2026-04-11 17:02:38',0,NULL,0,'robin',NULL,0,0,NULL,NULL);
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-04-12 19:48:30
