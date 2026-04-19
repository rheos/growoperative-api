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
) ENGINE=InnoDB AUTO_INCREMENT=688 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `inventories`
--

LOCK TABLES `inventories` WRITE;
/*!40000 ALTER TABLE `inventories` DISABLE KEYS */;
INSERT INTO `inventories` VALUES (657,1,4,43,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(658,3,7,37,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(659,2,8,9,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(660,7,9,43,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(661,5,10,7,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(662,5,11,6,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(663,10,12,9,5,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(664,10,13,7,5,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(665,1,14,11,5,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(666,7,15,6,5,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(667,6,16,41,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(668,13,17,10,6,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(669,4,18,9,5,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(670,12,19,7,3,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(671,8,82,39,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL),(672,11,83,8,4,1,'2026-04-17 20:30:30','2026-04-17 20:30:30',NULL,NULL,'---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n',NULL,NULL);
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
  `cancellation_reason` text COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`id`),
  KEY `index_item_requests_on_user_id` (`user_id`),
  KEY `index_item_requests_on_request_contract_id` (`request_contract_id`),
  CONSTRAINT `fk_rails_4962f18dcb` FOREIGN KEY (`request_contract_id`) REFERENCES `request_contracts` (`id`),
  CONSTRAINT `fk_rails_596a91ea22` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=404 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `item_requests`
--

LOCK TABLES `item_requests` WRITE;
/*!40000 ALTER TABLE `item_requests` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=84 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `items`
--

LOCK TABLES `items` WRITE;
/*!40000 ALTER TABLE `items` DISABLE KEYS */;
INSERT INTO `items` VALUES (4,1,43.00000,1,2,'Black Krim',5,4.00,'2025-06-22 06:39:54','2026-04-12 05:49:48','2026-04-14 02:32:10',1,1,1,'[\"1751364851823black_krim2.jpg\", \"1751364866030black_krim.jpg\"]'),(7,3,37.00000,1,3,'Arugula',5,4.00,'2025-06-22 08:33:16','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,3,'[\"17505812007801893957_130425174900_01112_grande.jpeg\", \"1750581208581arugula.jpg\"]'),(8,2,9.00000,1,4,'Basil',6,4.00,'2025-06-22 08:35:56','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,2,'[\"1750581370499basil-with-wet-leaves.jpg\", \"1750581377807basil3.jpg\"]'),(9,7,43.00000,1,6,'Black Cherry',5,4.00,'2025-06-22 08:38:23','2026-04-12 05:49:48','2026-04-14 02:32:11',1,0,7,'[\"1750581529454black_cherry_tomato_2.png\", \"1750581538258black_cherry_tomatoes.jpeg\"]'),(10,5,7.00000,1,7,'Curly Kale',5,4.00,'2025-06-22 08:40:36','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,5,'[\"1750581669721curly_kale_1.jpg\", \"1750581678247curly_kale.jpg\"]'),(11,5,6.00000,1,8,'Early Girl',6,4.00,'2025-06-22 08:53:25','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,5,'[\"1750582443485early_girl_1.png\", \"1750582450068early_girl_2.png\"]'),(12,10,9.00000,1,9,'Cabbage',5,5.00,'2025-06-22 08:55:27','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,10,'[\"1750582543038cabbage.jpg\", \"1750582550263cabbage2.jpg\"]'),(13,10,7.00000,1,10,'Fennel',6,5.00,'2025-06-22 08:57:47','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,10,'[\"1750582697783fennel.jpeg\", \"1750582705419fennel2.jpg\"]'),(14,1,11.00000,1,11,'Lemon Balm',6,5.00,'2025-06-22 08:59:09','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,1,'[\"1750582775973lemon_balm.jpg\", \"1750582803615Lemon_Balm.jpg\"]'),(15,7,6.00000,1,12,'Lettuce',5,5.00,'2025-06-22 09:00:54','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,7,'[\"1750582875945lettuce1.png\", \"1750582882996lettuce3.jpeg\"]'),(16,6,41.00000,1,13,'Mint',6,4.00,'2025-06-22 09:33:57','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,6,'[\"1750584870221mint1.png\", \"1750584879142mint2.png\", \"1750584889094mint3.png\"]'),(17,13,10.00000,1,14,'Hot Peppers',6,6.00,'2025-06-22 09:35:41','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,13,'[\"1750584955954pepper1.png\", \"1750584972672pepper2.jpeg\"]'),(18,4,9.00000,1,15,'Purple Cabbage',5,5.00,'2025-06-22 09:37:38','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,4,'[\"1750585076007purple_cabbage.jpg\", \"1750585082925purple-cabbage.jpg\"]'),(19,12,7.00000,1,17,'Russet Potatoes',6,3.00,'2025-06-22 09:39:10','2026-04-12 05:49:48','2026-04-14 02:32:11',1,1,12,'[\"1750585186332russet_potato_1.jpeg\", \"1750585245264russet_potato_2.jpeg\", \"1750585251749russet_potato_3.jpeg\"]'),(82,8,39.00000,1,2,'Apples',5,4.00,'2026-04-17 00:00:00','2026-04-17 19:43:56','2026-04-17 19:43:56',1,0,8,NULL),(83,11,8.00000,1,2,'Apples',5,4.00,'2026-04-17 00:00:00','2026-04-17 19:43:56','2026-04-17 19:43:56',1,0,11,NULL);
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
) ENGINE=InnoDB AUTO_INCREMENT=132 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `jwt_blacklist`
--

LOCK TABLES `jwt_blacklist` WRITE;
/*!40000 ALTER TABLE `jwt_blacklist` DISABLE KEYS */;
/*!40000 ALTER TABLE `jwt_blacklist` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `notifications`
--

DROP TABLE IF EXISTS `notifications`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `notifications` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `recipient_id` bigint(20) NOT NULL,
  `actor_id` bigint(20) DEFAULT NULL,
  `notification_type` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `actor_name` varchar(255) DEFAULT NULL,
  `actor_avatar_url` varchar(255) DEFAULT NULL,
  `target_type` varchar(255) DEFAULT NULL,
  `target_id` bigint(20) DEFAULT NULL,
  `target_screen` varchar(255) DEFAULT NULL,
  `metadata` json DEFAULT NULL,
  `read` tinyint(1) NOT NULL DEFAULT '0',
  `read_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_notifications_inbox` (`recipient_id`,`read`,`created_at`),
  KEY `index_notifications_timeline` (`recipient_id`,`created_at`),
  KEY `fk_rails_06a39bb8cc` (`actor_id`),
  CONSTRAINT `fk_rails_06a39bb8cc` FOREIGN KEY (`actor_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_4aea6afa11` FOREIGN KEY (`recipient_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=171 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `notifications`
--

LOCK TABLES `notifications` WRITE;
/*!40000 ALTER TABLE `notifications` DISABLE KEYS */;
/*!40000 ALTER TABLE `notifications` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=100214 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `orders`
--

LOCK TABLES `orders` WRITE;
/*!40000 ALTER TABLE `orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `pending_payments`
--

DROP TABLE IF EXISTS `pending_payments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pending_payments` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `from_user_id` bigint(20) DEFAULT NULL,
  `to_user_id` bigint(20) DEFAULT NULL,
  `trustline_id` bigint(20) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `description` text,
  `status` int(11) NOT NULL DEFAULT '0',
  `rejected_reason` text,
  `confirmed_at` datetime DEFAULT NULL,
  `resolved_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_pending_payments_on_from_user_id` (`from_user_id`),
  KEY `index_pending_payments_on_to_user_id` (`to_user_id`),
  KEY `index_pending_payments_on_trustline_id` (`trustline_id`),
  KEY `index_pending_payments_on_status` (`status`),
  CONSTRAINT `fk_rails_24d87784fd` FOREIGN KEY (`to_user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_8de6e56bec` FOREIGN KEY (`from_user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_rails_ed9175c848` FOREIGN KEY (`trustline_id`) REFERENCES `trustlines` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `pending_payments`
--

LOCK TABLES `pending_payments` WRITE;
/*!40000 ALTER TABLE `pending_payments` DISABLE KEYS */;
/*!40000 ALTER TABLE `pending_payments` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=255 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `request_contracts`
--

LOCK TABLES `request_contracts` WRITE;
/*!40000 ALTER TABLE `request_contracts` DISABLE KEYS */;
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
INSERT INTO `schema_migrations` VALUES ('20181005144412'),('20181005161210'),('20181009105102'),('20181009105826'),('20181009141123'),('20181010011344'),('20181010011709'),('20181010044205'),('20181015111634'),('20181015141508'),('20181016141706'),('20181016141800'),('20181019080406'),('20181019084146'),('20181019085108'),('20181022081506'),('20181022104338'),('20181022105107'),('20181023113502'),('20181024082439'),('20181025083930'),('20181101125759'),('20181101131408'),('20181102052157'),('20181102054039'),('20181102063418'),('20181102064500'),('20181102064853'),('20181102064916'),('20181102065037'),('20181102065448'),('20181102071750'),('20181102075815'),('20181102095604'),('20181102095826'),('20181102100117'),('20181102100234'),('20181102100454'),('20181103110803'),('20181104093029'),('20181105104929'),('20181105105333'),('20181105105920'),('20181105110239'),('20181105110406'),('20181105110627'),('20181105110700'),('20181105110724'),('20181105110759'),('20181105124606'),('20181106025354'),('201811070122202'),('20181114011154'),('20181128200407'),('20181128201905'),('20181128201926'),('20181128202024'),('20181128202057'),('20181128202212'),('20181201023333'),('20190108214619'),('20190111081833'),('20190113133724'),('20190113171909'),('20190115062006'),('20190116141205'),('20190128202223'),('20190201024857'),('20190201073738'),('20190201193545'),('20190629103608'),('20190629105212'),('20190702083532'),('20190702084144'),('20190708202239'),('20190715085203'),('20190719105604'),('20190719175607'),('20190719183221'),('20190801190819'),('20190802122405'),('20200212124528'),('20200212142201'),('20200213084015'),('20200323220353'),('20200415144533'),('20200416160821'),('20200416171441'),('20200420161824'),('20200422152529'),('20200425230910'),('20200426143411'),('20200426173808'),('20200429124328'),('20250624085633'),('20250624100523'),('20260410211409'),('20260410233422'),('20260412221544'),('20260413014036'),('20260413130000'),('20260413200000'),('20260415120000'),('20260415220000');
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
) ENGINE=InnoDB AUTO_INCREMENT=40 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
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
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
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
  `foaf_address` varchar(42) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `foaf_public_key` text COLLATE utf8mb4_unicode_ci,
  `foaf_private_key` text COLLATE utf8mb4_unicode_ci,
  `foaf_registered` tinyint(1) DEFAULT '0',
  `foaf_seed_phrase` text COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_users_on_user_name` (`user_name`),
  UNIQUE KEY `index_users_on_email` (`email`),
  UNIQUE KEY `index_users_on_reset_password_token` (`reset_password_token`),
  UNIQUE KEY `index_users_on_foaf_address` (`foaf_address`),
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
INSERT INTO `users` VALUES (1,'$2a$11$Dt.Vw2TMVGfRQuEyD4xEsexJe1aAjYCJivHh18AZYzljofapQiW9S',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:48',NULL,NULL,4,'bob',NULL,0,1000000,NULL,NULL,'0x1e7aecead6942dbc246f57afae094b372c08c4d6','049cd4d9ac4dd04c25f4d904ab325a3afaa776a87d92e4de849b61113ee4c55f3272d1b96dbd7123201ec826d9a43633e46908b997c7efdc81a4880a08a963a520','46e1d39b359d120e8e58c8f7aa23aa0fab726f4b0911ee30eaf0b7c294eb7e93',0,'math beef patch author loyal early staff impulse involve mercy donor imitate'),(2,'$2a$11$Dy0fJl6zSlR9Ta31lWzEX.Ti1U4xPP1U249CO8zazZ33WVe5dwIwy',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:44',NULL,NULL,0,'dianna',NULL,1,3,'JZA7SNVP',1,'0x8344167060c049088be64f388e8df4857cdcce75','04ce82c5493517d94bfc9d1d8ad9cdca3f6a1e789eefb8403b679d5587433f81c88f64d75abc5682b90a3f4a7263426408d344a723dc1786008d65a87739ddda79','add98451b9f3d70c09597b9ad63d438354e28b2c8c7338f28157ed00830a5c93',0,'lawsuit method glare erode drink shift bid social gloom cradle liar begin'),(3,'$2a$11$Yga6dIGVTWDvyASc0x9zg.RlwziEGW2TAkWQE7MhnzHaexgAMMtPG',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:44','2025-06-18 01:07:46',NULL,NULL,3,'peter',NULL,1,3,'G71N3T0S',1,'0xbc5f5c5086ef2459121c41e0f78ec7b8e01bf479','040ac66fe9497bb86e57864706ae13447349c04fb19de4844b1143893b4c57448fbdd26aafb185e48f2c5bfd75a6b68b8ac50314f707bedd7ca353da575799e76c','83b8a70ffd89717c9cf12158a0f66cc4b6381a7e672771976119ab8d770a6957',0,'walk receive diet asthma able budget shoot decade small decrease type nerve'),(4,'$2a$11$0/gjhS8E0zn4.SlS3VBaP.rEbKpCCzRFE.pzd633MpP6d64UULXui',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:45','2025-06-18 01:07:45',NULL,NULL,0,'paul',NULL,2,3,'MQJK3BG5',3,'0x0646fd56f29e249da8f4b6bedbdfa1e1a72161e6','0425e97a74f1f6c086ac92421d059277c76eeb935e0d7b151b821fd35839fc353181a42f46202333ead4bf17f0753a1742d63685ca3798d49b6fc3c9569900606b','95ccc714590717ed38fa53351810995d0c563c5c1ea05d59210903279b587c1d',0,'finger snack east boss tail produce like jump cricket social dry steel'),(5,'$2a$11$YSHc9lmpuWhHpz0i.ZTxTe5YTXn.fw67NJmXDTMLQjfO1ynsHqrhi',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:45','2025-06-18 01:07:45',NULL,NULL,0,'sara',NULL,2,3,'NJ2QPLW0',3,NULL,NULL,NULL,0,NULL),(6,'$2a$11$wvMEx6pdPO15iFV0qGbOaOHHYhBgP9uh8NfUvdqPKW.e5Vgvzi4ka',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:46','2025-06-18 01:07:46',NULL,NULL,0,'mary',NULL,2,3,'UZSGTY3V',3,'0x24c2df03db026b10e7b683586a48678515bb3844','04d00d7349a92f4cc98a9727602442a3065baab6c0ab1144a228faf5c9e41eb31356c03c6e502524552d807fb1c5d9bfd399a8b5aad00ec82d0bae70f9e715a5ba','ca2dacd2fcf94509c04cb395c0196c0ebde379c0fce1358d22c8595b4eb805a3',0,'farm mad way urban alpha maximum worry security insane blouse useful helmet'),(7,'$2a$11$WHTheF8F8aK4qfxGN5HyJuTvm9Q5S0toIgt3VsIB6pJFl7PDCBsym',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:46','2025-06-30 08:41:03',NULL,NULL,2,'bruce',NULL,1,7,'H4KC2AJS',1,'0x5a92f2ecf897cc8d443341b34643ba937c03ca80','0498b8e5d946f284becf6ba1980c51fad7c57bbf77e9a5d159ca8181ab65332445ea83912d7148f15d6073070945c4bb616b3455057dfbdcfd4be1db5dc1375fce','c712caab2af583b0df7776540290704344599d4fe342b4f2f824e59866a60553',0,'dizzy slim fresh token town current gravity tag orphan knife spread exchange'),(8,'$2a$11$HKtxADkSmPBaTC4zrK2dJeTAc1gpgKPNBcb/PQ.1ik6R0wpIdmmpS',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:47','2025-06-18 01:07:47',NULL,NULL,1,'arthur',NULL,2,3,'6DN58LU1',7,'0x4afe2e428d1b4955660aeab42c0484d58235af9a','0446704c71abe0b763c981c31862e2e7dbee243aa1bbae015c1a59c842dbad86db7b4ce119705cbc225607c2e0b80c7a68df3bbeca09b3e73df64e5d94705d3cf3','4ba7fb523edb2d73621dc5dc4181e532dbcc9141b0e6aa008783844ea2eaa31d',0,'age chicken tag wish magnet cloud super pluck extra educate priority fall'),(9,'$2a$11$.ii/6sDsJvghPXP8zYVJ8ONu2kD6zCAmWlr5oVPC9nHeIXgo6wJT2',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:47','2025-06-18 01:07:47',NULL,NULL,0,'mark',NULL,3,3,'NMEZVDL0',8,NULL,NULL,NULL,0,NULL),(10,'$2a$11$fSYusSBihmL3Z9ksjTE.Ce4OaaBFYE1YmgHG0AOn616baHRldK3y2',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:48','2025-06-18 01:07:48',NULL,NULL,1,'clark',NULL,1,3,'I3U8KDJW',1,'0x19c09ad58d67ed7ab5e9bc4e6e5c30cd263fe75d','04470d0d593385def5df53aa08aeca5c0e30fdb9c1dd53c55d939f13d10ce90f59abccdd0e0b4f75515a74e16c037f9d4c0e61194fa235f21393a8a3eaff239465','7efcacab00d8ffab9a9620dcaf86f5f711cc6484bd993a42078ce785e58bc949',0,'luggage patrol sing egg smart aisle educate choice govern protect claw rate'),(11,'$2a$11$UQigDwidGR5pg2NvQHCDSO6n4xWodxlW.oCBSu1LSepMOG.PjB.xy',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:48','2025-06-18 01:07:48',NULL,NULL,0,'oliver',NULL,2,3,'KGR7LN08',10,'0xd87a80e5e16b64601d764528055fa39e3531e44e','047883a0e5f6716ce4b423a54cd6d770b6f9a9c95af59a93b2cf2d69b7391577c27e0a0150ef9f7f63fa1ce99442172b3ce7e749e0c320b0ead9989e1bcd639f22','f9610a4b4944b22c4bf0f75949ef9a8100bba546bdfa57f66f3c1eab12c09c52',0,'twelve excite awful noodle glad amazing sentence carpet web rifle toy capable'),(12,'$2a$11$4CymLEbq.hkRBypwTjQifOQ1I7UOoIBLpCEtcjQSAGmlSAPQN5aRG',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,'avatar.jpg',NULL,NULL,'2025-06-18 01:07:48','2026-04-11 22:24:03',NULL,NULL,1,'barry',NULL,2,3,'EDB2P85X',7,'0xe5d63f0acce7a4d2a406bf1de150cdd52c31db5e','043309d4559c24aa603a81eb7e2e380369912160cc7f2f0b830290ed77e848566fcb7f9d1800e156536be9e4697cf23d42a7f4c34429521e00d4ed115190b13fc0','52597e5cae925af3a5e21860a3eaf213b9b34ef454b5ee85490d42108ccbeb8a',0,'lazy pizza often slam diamond bunker caution tired what spare surround loud'),(13,'$2a$11$yYCvydy.w6s0w3f2MGSxF.svWWbPGQZwA1Ys5xvVCETy.mzynf9/q',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2025-06-18 01:07:49','2025-06-18 01:07:49',NULL,NULL,0,'john',NULL,3,3,'2J46IVHR',12,'0x458ce85ee0091fb2eeaee8c41161a31828b7dfb5','0417c624ea022782bd1cafe7de2f0b420c6d72f747644181a8a166d380c60b3a8fca2504cb3026b7c5193a8d4bc1d7a883e1913ed8c1c8dc5f329fc8ad2099322d','2640bbebfa8b6e464ecaf0c21e607e4ca2a4f7c906fff9754ba9605d1d2fc708',0,'smart review quit empty verb empty prevent sausage cherry actress arrow battle'),(14,'$2a$11$1Yo8aVzrUKTnVlis7.1K6u8gwE2UNvzO/u5RdSXs1xIqWqsKwHZry',NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-04-10 17:05:56','2026-04-16 05:57:42',0,NULL,0,'robin',NULL,0,0,NULL,NULL,NULL,NULL,NULL,0,NULL);
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

-- Dump completed on 2026-04-17 20:30:30
